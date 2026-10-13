local install=assert(loadfile('config/hammerspoon/cleanup.lua'))()
local dead={id=function() return 1 end,frame=function() return {w=0,h=0} end}
local focuses=0
local live={focus=function() focuses=focuses+1 end,id=function() return 2 end,frame=function() return {x=-999,w=500,h=800} end}
hs={spaces={focusedSpace=function() return 11 end},window={focusedWindow=function() return live end}}
local indexed={[1]=true,[2]=true};local removed,forwarded,tiles=0,0,0
local paperwm={
 events={windowEventHandler=function() forwarded=forwarded+1 end},
 floating={isFloating=function() return false end},
 state={get=function() return {window_list={[11]={{dead},{live}}}} end,
 windowIndex=function(w) return indexed[w:id()] and {space=11} end},
 windows={removeWindow=function(w,skip) assert(skip);indexed[w:id()]=nil;removed=removed+1;return 11 end},
 tileSpace=function() tiles=tiles+1 end,
}
local prune=install(paperwm)
prune();assert(removed==1 and indexed[2] and tiles==1,'Closed windows must be removed without discarding valid offscreen windows')
prune();assert(removed==1,'Cleanup must be idempotent')
indexed[1]=true
paperwm.events.windowEventHandler(dead,'windowDestroyed',paperwm)
assert(removed==2 and forwarded==0,'Destroy event must remove lingering managed window')
paperwm.events.windowEventHandler(dead,'windowDestroyed',paperwm)
assert(removed==2,'Duplicate destroy must not remove another window')
paperwm.events.windowEventHandler(live,'windowFocused',paperwm)
assert(forwarded==1,'Normal events must retain upstream handling')
indexed[1]=true
hs.window.focusedWindow=function() return nil end
prune();assert(focuses==1,'Closing last Finder window must restore a live navigation anchor')
print('Closed-window cleanup checks passed')
