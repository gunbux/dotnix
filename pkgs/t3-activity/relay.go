package main

// T3 Connect: the activity of every linked environment, as the phone sees it.
//
// This mirrors the mobile app. The desktop app's Clerk client token (in
// clerk-tokens.json, encrypted with Electron safeStorage under a keyring
// password) buys a "t3-relay" session JWT from Clerk; the relay exchanges that
// for a DPoP-bound access token, which reads /v1/mobile/agent-activity. Only
// the t3-mobile client may ask for the mobile:registration scope that read
// needs. Requests are read-only and leave the desktop's stored token alone.

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	clerkFrontendAPI = "https://clerk.t3.codes"
	clerkJWTTemplate = "t3-relay"
	relayURL         = "https://relay.t3.codes"
	relayRetry       = 60 * time.Second
	environmentsTTL  = time.Hour
)

// Electron names the keyring entry after the app; older installs used Alpha.
var keyringApplications = []string{"T3 Code (Beta)", "T3 Code (Alpha)", "T3 Code"}

// secretTool is libsecret's CLI; Nix sets the store path via -ldflags.
var secretTool = "secret-tool"

var b64 = base64.RawURLEncoding

var httpClient = &http.Client{Timeout: 8 * time.Second}

type activityRow struct {
	EnvironmentID string `json:"environmentId"`
	ThreadID      string `json:"threadId"`
	ProjectTitle  string `json:"projectTitle"`
	ThreadTitle   string `json:"threadTitle"`
	ModelTitle    string `json:"modelTitle"`
	Phase         string `json:"phase"`
	UpdatedAt     string `json:"updatedAt"`
	DeepLink      string `json:"deepLink"`
}

// relayCache lives in $XDG_RUNTIME_DIR so each poll does not repeat the
// token exchange.
type relayCache struct {
	Key          string            `json:"key"`
	AccessToken  string            `json:"accessToken"`
	ExpiresAt    time.Time         `json:"expiresAt"`
	Environments map[string]string `json:"environments"`
	EnvsAt       time.Time         `json:"envsAt"`
	Rows         []activityRow     `json:"rows"`
	RowsAt       time.Time         `json:"rowsAt"`
	Error        string            `json:"error"`
	ErrorAt      time.Time         `json:"errorAt"`
}

type relayStatus struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

func cachePath() string {
	return runtimePath("relay.json")
}

func runtimePath(name string) string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "t3-activity", name)
}

func writeRuntime(name string, value any) {
	path := runtimePath(name)
	os.MkdirAll(filepath.Dir(path), 0o700)
	raw, _ := json.Marshal(value)
	tmp := path + ".tmp"
	if os.WriteFile(tmp, raw, 0o600) == nil {
		os.Rename(tmp, path)
	}
}

// seen.json maps a remote thread opened from the pill to the relay row's
// updatedAt at the time, so it reappears once the thread finishes again.
func readSeen() map[string]string {
	seen := map[string]string{}
	if raw, err := os.ReadFile(runtimePath("seen.json")); err == nil {
		json.Unmarshal(raw, &seen)
	}
	return seen
}

func markSeen(threadID string) {
	for _, row := range loadCache().Rows {
		if row.ThreadID == threadID {
			seen := readSeen()
			seen[threadID] = row.UpdatedAt
			writeRuntime("seen.json", seen)
			return
		}
	}
}

// loadSeen returns the seen marks, forgetting threads the relay has dropped.
func loadSeen(rows []activityRow) map[string]string {
	seen := readSeen()
	if rows == nil {
		return seen // relay unreachable; keep the marks
	}
	live := map[string]bool{}
	for _, row := range rows {
		live[row.ThreadID] = true
	}
	pruned := false
	for id := range seen {
		if !live[id] {
			delete(seen, id)
			pruned = true
		}
	}
	if pruned {
		writeRuntime("seen.json", seen)
	}
	return seen
}

func loadCache() *relayCache {
	c := &relayCache{}
	if raw, err := os.ReadFile(cachePath()); err == nil {
		json.Unmarshal(raw, c)
	}
	return c
}

func (c *relayCache) save() {
	writeRuntime("relay.json", c)
}

// relayActivity returns every linked environment's activity rows and their
// labels, refreshing from the relay at most once per interval.
func relayActivity(userdata string, interval time.Duration) ([]activityRow, map[string]string, relayStatus) {
	c := loadCache()
	now := time.Now()
	if c.Error != "" && now.Sub(c.ErrorAt) < relayRetry {
		return nil, c.Environments, relayStatus{Error: c.Error}
	}
	if c.Error == "" && now.Sub(c.RowsAt) < interval {
		return c.Rows, c.Environments, relayStatus{OK: true}
	}

	err := c.refresh(userdata)
	if err != nil {
		c.Error, c.ErrorAt = err.Error(), now
		c.save()
		return nil, c.Environments, relayStatus{Error: c.Error}
	}
	c.Error = ""
	c.save()
	return c.Rows, c.Environments, relayStatus{OK: true}
}

func (c *relayCache) refresh(userdata string) error {
	key, err := c.proofKey()
	if err != nil {
		return err
	}
	now := time.Now()
	if c.AccessToken == "" || now.Add(time.Minute).After(c.ExpiresAt) || now.Sub(c.EnvsAt) > environmentsTTL {
		session, err := clerkSessionJWT(userdata)
		if err != nil {
			return err
		}
		if err := c.exchange(key, session); err != nil {
			return err
		}
		if envs, err := listEnvironments(session); err == nil {
			c.Environments, c.EnvsAt = envs, now
		}
	}

	rows, status, err := agentActivity(key, c.AccessToken)
	if status == http.StatusUnauthorized {
		c.AccessToken = "" // revoked or expired early; exchange again next poll
	}
	if err != nil {
		return err
	}
	c.Rows, c.RowsAt = rows, now
	return nil
}

// proofKey loads the cached P-256 DPoP key, minting one on first use. The
// access token is bound to it, so the two are cached together.
func (c *relayCache) proofKey() (*ecdsa.PrivateKey, error) {
	if der, err := base64.StdEncoding.DecodeString(c.Key); err == nil && len(der) > 0 {
		if k, err := x509.ParseECPrivateKey(der); err == nil {
			return k, nil
		}
	}
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	der, err := x509.MarshalECPrivateKey(k)
	if err != nil {
		return nil, err
	}
	c.Key, c.AccessToken = base64.StdEncoding.EncodeToString(der), ""
	return k, nil
}

// clerkSessionJWT decrypts the desktop's Clerk client token and asks Clerk
// for a short-lived session JWT from the relay's template.
func clerkSessionJWT(userdata string) (string, error) {
	clientToken, err := desktopClientToken(userdata)
	if err != nil {
		return "", err
	}
	var client struct {
		Response struct {
			LastActiveSessionID string `json:"last_active_session_id"`
		} `json:"response"`
	}
	if err := clerkRequest("GET", "/v1/client", clientToken, &client); err != nil {
		return "", err
	}
	sid := client.Response.LastActiveSessionID
	if sid == "" {
		return "", errors.New("T3 Code desktop is signed out of T3 Connect")
	}
	var token struct {
		JWT string `json:"jwt"`
	}
	if err := clerkRequest("POST", "/v1/client/sessions/"+sid+"/tokens/"+clerkJWTTemplate, clientToken, &token); err != nil {
		return "", err
	}
	if token.JWT == "" {
		return "", errors.New("clerk returned no session token")
	}
	return token.JWT, nil
}

func clerkRequest(method, path, clientToken string, out any) error {
	req, err := http.NewRequest(method, clerkFrontendAPI+path+"?_is_native=1", nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", clientToken)
	return doJSON(req, out)
}

// desktopClientToken reads the Clerk client token the desktop app stored via
// @clerk/electron: "enc:" + base64 of Chromium's "v11" safeStorage format,
// AES-128-CBC under PBKDF2(keyring password, "saltysalt", 1 round).
func desktopClientToken(userdata string) (string, error) {
	raw, err := os.ReadFile(filepath.Join(userdata, "clerk-tokens.json"))
	if err != nil {
		return "", errors.New("T3 Code desktop has not signed in to T3 Connect")
	}
	var stored map[string]string
	if err := json.Unmarshal(raw, &stored); err != nil {
		return "", err
	}
	value := stored["__clerk_client_jwt"]
	if plain, ok := strings.CutPrefix(value, "raw:"); ok {
		return plain, nil
	}
	sealed, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(value, "enc:"))
	if err != nil || len(sealed) < 3+aes.BlockSize || string(sealed[:3]) != "v11" {
		return "", errors.New("unrecognised Clerk token encryption")
	}
	sealed = sealed[3:]
	for _, app := range keyringApplications {
		password, err := exec.Command(secretTool, "lookup",
			"xdg:schema", "chrome_libsecret_os_crypt_password_v2", "application", app).Output()
		if err != nil || len(password) == 0 {
			continue
		}
		if token, ok := safeStorageDecrypt(sealed, strings.TrimSpace(string(password))); ok {
			return token, nil
		}
	}
	return "", errors.New("could not decrypt the desktop's Clerk token with the keyring")
}

func safeStorageDecrypt(sealed []byte, password string) (string, bool) {
	if len(sealed)%aes.BlockSize != 0 {
		return "", false
	}
	key, err := pbkdf2.Key(sha1.New, password, []byte("saltysalt"), 1, 16)
	if err != nil {
		return "", false
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", false
	}
	out := make([]byte, len(sealed))
	cipher.NewCBCDecrypter(block, []byte(strings.Repeat(" ", aes.BlockSize))).CryptBlocks(out, sealed)
	pad := int(out[len(out)-1])
	if pad < 1 || pad > aes.BlockSize {
		return "", false
	}
	token := string(out[:len(out)-pad])
	if strings.Count(token, ".") != 2 {
		return "", false
	}
	return token, true
}

func (c *relayCache) exchange(key *ecdsa.PrivateKey, session string) error {
	tokenURL := relayURL + "/v1/client/dpop-token"
	form := url.Values{
		"grant_type":           {"urn:ietf:params:oauth:grant-type:token-exchange"},
		"subject_token":        {session},
		"subject_token_type":   {"urn:ietf:params:oauth:token-type:jwt"},
		"requested_token_type": {"urn:ietf:params:oauth:token-type:access_token"},
		"resource":             {relayURL},
		"scope":                {"mobile:registration"},
		"client_id":            {"t3-mobile"},
	}
	req, err := http.NewRequest("POST", tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("DPoP", dpopProof(key, "POST", tokenURL, ""))
	var token struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := doJSON(req, &token); err != nil {
		return fmt.Errorf("relay token exchange: %w", err)
	}
	c.AccessToken = token.AccessToken
	c.ExpiresAt = time.Now().Add(time.Duration(token.ExpiresIn) * time.Second)
	return nil
}

func listEnvironments(session string) (map[string]string, error) {
	req, err := http.NewRequest("GET", relayURL+"/v1/environments", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+session)
	var out struct {
		Environments []struct {
			EnvironmentID string `json:"environmentId"`
			Label         string `json:"label"`
		} `json:"environments"`
	}
	if err := doJSON(req, &out); err != nil {
		return nil, err
	}
	labels := map[string]string{}
	for _, env := range out.Environments {
		labels[env.EnvironmentID] = env.Label
	}
	return labels, nil
}

func agentActivity(key *ecdsa.PrivateKey, accessToken string) ([]activityRow, int, error) {
	u := relayURL + "/v1/mobile/agent-activity"
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, 0, err
	}
	ath := sha256.Sum256([]byte(accessToken))
	req.Header.Set("Authorization", "DPoP "+accessToken)
	req.Header.Set("DPoP", dpopProof(key, "GET", u, b64.EncodeToString(ath[:])))
	var out struct {
		Aggregate *struct {
			Activities []activityRow `json:"activities"`
		} `json:"aggregate"`
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	if err := decodeResponse(resp, &out); err != nil {
		return nil, resp.StatusCode, fmt.Errorf("relay agent activity: %w", err)
	}
	if out.Aggregate == nil {
		return []activityRow{}, resp.StatusCode, nil
	}
	return out.Aggregate.Activities, resp.StatusCode, nil
}

// dpopProof signs an RFC 9449 proof the way the web client's jose SignJWT
// does. ath binds it to an access token on resource requests.
func dpopProof(key *ecdsa.PrivateKey, method, target, ath string) string {
	header, _ := json.Marshal(map[string]any{
		"typ": "dpop+jwt",
		"alg": "ES256",
		"jwk": map[string]string{
			"kty": "EC",
			"crv": "P-256",
			"x":   b64.EncodeToString(key.X.FillBytes(make([]byte, 32))),
			"y":   b64.EncodeToString(key.Y.FillBytes(make([]byte, 32))),
		},
	})
	jti := make([]byte, 16)
	rand.Read(jti)
	claims := map[string]any{"htm": method, "htu": target, "jti": b64.EncodeToString(jti), "iat": time.Now().Unix()}
	if ath != "" {
		claims["ath"] = ath
	}
	payload, _ := json.Marshal(claims)
	input := b64.EncodeToString(header) + "." + b64.EncodeToString(payload)
	digest := sha256.Sum256([]byte(input))
	r, s, _ := ecdsa.Sign(rand.Reader, key, digest[:])
	// noble-curves, which verifies on the relay, wants low-S signatures.
	n := elliptic.P256().Params().N
	if s.Cmp(new(big.Int).Rsh(n, 1)) > 0 {
		s = new(big.Int).Sub(n, s)
	}
	sig := append(r.FillBytes(make([]byte, 32)), s.FillBytes(make([]byte, 32))...)
	return input + "." + b64.EncodeToString(sig)
}

func doJSON(req *http.Request, out any) error {
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return decodeResponse(resp, out)
}

func decodeResponse(resp *http.Response, out any) error {
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		var e struct {
			Reason string `json:"reason"`
		}
		json.Unmarshal(body, &e)
		if e.Reason != "" {
			return fmt.Errorf("%s: %s", resp.Status, e.Reason)
		}
		return errors.New(resp.Status)
	}
	return json.Unmarshal(body, out)
}
