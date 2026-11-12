return function(T)
T.test('startup view draws the user logo and a centered KDASH label on a clean frame',function()
 local calls={};local d={width=1072,height=1448}
 function d:begin_frame(full) calls[#calls+1]={'begin',full} end
 function d:icon(path,x,y,w,h) calls[#calls+1]={'icon',path,x,y,w,h} end
 function d:text(o) calls[#calls+1]={'text',o} end
 function d:flush(o) calls[#calls+1]={'flush',o};return true end
 T.truthy(require('ui.splash').render(d,'/app'))
 T.eq(calls[1][1],'begin');T.eq(calls[1][2],true)
 T.eq(calls[2][2],'/app/assets/logo-user.ttf')
 T.eq(calls[3][2].text,'KDASH');T.eq(calls[3][2].align,'center')
 T.eq(calls[4][2].full,true)
end)
end
