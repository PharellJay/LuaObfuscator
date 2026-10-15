local _rgefy8bgizwt=function(s,k)local function x(a,b)local r,m=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+m end a=math.floor(a/2)b=math.floor(b/2)m=m*2 end return r end local i=0 local k1=k%65521;local k2=math.floor(k/65521)%65521;return s:gsub(".",function(c)i=i+1 local ki=((k1*31+k2*17+i*13)%255)+1 local cb=c:byte() if i%2==1 then return string.char(x(cb,ki))else return string.char((x(cb,i)-ki+256)%256)end end)end;local _avbebfqi03qn=function(s,k)local function w(u,v)local p,q=0,1 while u>0 or v>0 do if u%2~=v%2 then p=p+q end u=math.floor(u/2)v=math.floor(v/2)q=q*2 end return p end local i=0 local k1=k%65521;local k2=math.floor(k/65521)%65521;return s:gsub(".",function(c)i=i+1 local ki=((k1*23+k2*13+i*7)%255)+1 local cb=c:byte() if i%2==1 then return string.char((cb-ki+256)%256)else return string.char(w(cb,ki))end end)end;local _humiwavqej4w={tonumber((_avbebfqi03qn("\030\204\052\054\062\035\075\039\087",(0x322f4006-0x1576)))),tonumber((_avbebfqi03qn("\175\188\191\161\201\147\220",(0x1696*0x270f+0x254a9222)))),tonumber((_avbebfqi03qn("\063\033\077\021\089\001\103\006\120",(0x1d26*0x270f+0x18e1f1b6)))),tonumber(((function()return _avbebfqi03qn("\245\249\009\234\018\211\036\193",(0x152033ed+0xbc-0x1fd4))end)())),tonumber((_avbebfqi03qn("\064\046\086\017\100\007\110\119\127",(0x30569cd+0x16a-0xbb81)))),tonumber((_avbebfqi03qn("\246\255\000\238\021\209\032\196",(0x25+0x100+0x1fa+0x3134d117)))),tonumber((_avbebfqi03qn("\118\121\139\111\153\086\160\076",(0x2387e726+0x1d8-0x957f)))),tonumber((_avbebfqi03qn("\030\223\045\203\061\063\070\040",(0xab93475+0x1cf1ce9)))),tonumber((_avbebfqi03qn("\218\154\232\139\249\255\003\238\021",(0x38ca7af2-0xb1d7)))),tonumber(((function()return _avbebfqi03qn("\179\180\195\165\205\146\223",(0x2dbf0218+0x8cb503c))end)())),tonumber((_avbebfqi03qn("\077\042\089\018\106\001",(0x335475bd+0x11d-0x46c1)))),tonumber(((function()return _avbebfqi03qn("\083\026\097\015\119\118\132\099",(0x2abee405-0x38ac))end)())),tonumber((_avbebfqi03qn("\136",(0x1db8bb71+0x9259f89)))),tonumber((_avbebfqi03qn("\068\042\081\021\096\002\109\115",(0x96c*0x270f+0x2e3f8f41)))),tonumber((_avbebfqi03qn("\045\049\062\032\080\046\087\025\105",(0x88+0x342+0x2b2+0x284a6015)))),tonumber((_avbebfqi03qn("\041\203\060\057\076\046\089\028",(0x381a5fe3-0x3fd8)))),tonumber((_avbebfqi03qn("\254\225\018\211\030\219\045",(0xfb+0x3bb+0x6c+0x3a7b1c4a)))),tonumber((_avbebfqi03qn("\252\224\013\231\024\219\042",(0x22ecae01+0x162f4d57)))),tonumber((_avbebfqi03qn("\149\092\168\077\178\183",(0x12c2b0b2+0x177-0xb173)))),tonumber(((function()return _avbebfqi03qn("\056\062\070\045\085\016\100",(0x1b0+0x2f1+0x103+0x28d67e9d))end)())),tonumber((_avbebfqi03qn("\229\136\245\242\002\224\019",(0x39d33e64+0x90-0x1bae)))),tonumber((_avbebfqi03qn("\044\048\061\033\075\039\088\020\107",(0x2090a9ed+0xed-0x2427)))),tonumber((_avbebfqi03qn("\137\100\148\089\167\079\176",(0x29404a00+0x1e9-0xa507)))),tonumber((_avbebfqi03qn("\113\113\124\106\140\080\158\089",(0x12ca*0x270f+0x17a80fc3)))),tonumber((_avbebfqi03qn("\249\250\008\224\021\214\037\195",(0x127+0x285+0xec+0x11527c87)))),tonumber((_avbebfqi03qn("\250\228\008\237\027\222\041",(0x2bd1b743-0xc199)))),tonumber((_avbebfqi03qn("\179\186\191\167\211\147",(0x187+0x2a4+0x104+0x30d82338)))),_rgefy8bgizwt("\027\231\244\219\205\022\241\050\153\060\168\071\106\140\084\103\085\162\057",(0x287+0x198+0xe8+0x1dd6eb2d)),_rgefy8bgizwt("\172\053\149\119\116\150\117\140\045\177\049\237\056\249\224\233\252\015\174",(0x14afc60b+0x7850a7f)),tonumber((_avbebfqi03qn("\152\085\172\077\182\191",(0x208+0x393+0x71+0x3e8cb66)))),tonumber(((function()return _avbebfqi03qn("\098\015\119\125\125\099",(0x1aaff146-0x2375))end)())),tonumber((_avbebfqi03qn("\166\073\177\187\194\174",(0x16f7*0x270f+0x1944c3)))),tonumber(((function()return _avbebfqi03qn("\189\160\210\147\223\150",(0x211+0x3ba+0x1ab+0x1fc4fa73))end)())),tonumber((_avbebfqi03qn("\244\250\253\227\014\236",(0x76c*0x270f+0x17f28890)))),_rgefy8bgizwt("\193\012\248\004\168\067\169\062\114\120\076\147\098\162\037",(0x1d9bcea6+0x1858bd1f)),tonumber(((function()return _avbebfqi03qn("\042\205\054\059\073",(0xde497ce+0x40-0xa99))end)())),tonumber(((function()return _avbebfqi03qn("\186\190\205\173\218\147",(0xb+0xe+0x22c+0x24845dca))end)())),_rgefy8bgizwt("\246\220\248\008\252\063\156\055\157\083",(0x3aa+0xbe+0x274+0x16d575f5)),_rgefy8bgizwt("\229\031\162\060\190\043\156\096\086",(0x3e8cd26+0x321c2c1)),tonumber((_avbebfqi03qn("\148\095\165\078\176\177",(0x3964ee34-0x60b7))))};local _yoshlrxs45sk=(function() local a=0 for b=1,19 do a=(a+b*110)%256 end return a end)();local _qvi1qabcym3d={(function(k,e1,e2,e3,e4,e5,e6,e7)local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char((x(e1,k)-_yoshlrxs45sk)%256,(x(e2,k)-_yoshlrxs45sk)%256,(x(e3,k)-_yoshlrxs45sk)%256,(x(e4,k)-_yoshlrxs45sk)%256,(x(e5,k)-_yoshlrxs45sk)%256,(x(e6,k)-_yoshlrxs45sk)%256,(x(e7,k)-_yoshlrxs45sk)%256)end)(295359215,295359212,295359212,295359208,295359231,295359228,295359224,295359206),(function(k,e1,e2,e3,e4,e5,e6)local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char((x(e1,k)-_yoshlrxs45sk)%256,(x(e2,k)-_yoshlrxs45sk)%256,(x(e3,k)-_yoshlrxs45sk)%256,(x(e4,k)-_yoshlrxs45sk)%256,(x(e5,k)-_yoshlrxs45sk)%256,(x(e6,k)-_yoshlrxs45sk)%256)end)(517237425,517237430,517237409,517237410,517237414,517237432,517237433),(function(k,e1,e2,e3,e4,e5,e6)local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char((x(e1,k)-_yoshlrxs45sk)%256,(x(e2,k)-_yoshlrxs45sk)%256,(x(e3,k)-_yoshlrxs45sk)%256,(x(e4,k)-_yoshlrxs45sk)%256,(x(e5,k)-_yoshlrxs45sk)%256,(x(e6,k)-_yoshlrxs45sk)%256)end)(430075404,430075393,430075422,430075419,430075393,430075396,430075397),(function(k,e1,e2,e3,e4,e5)local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char((x(e1,k)-_yoshlrxs45sk)%256,(x(e2,k)-_yoshlrxs45sk)%256,(x(e3,k)-_yoshlrxs45sk)%256,(x(e4,k)-_yoshlrxs45sk)%256,(x(e5,k)-_yoshlrxs45sk)%256)end)(343712050,343712055,343712056,343712042,343712059,343712036)};local function _rwl4gek1oljp()
while true do
local _r4anxvrj94nr={};
local _rrq07jhrmoq1=false;
local _64etuvsbptod;
local _e6me00viib8f={};
local function _8gldk1nc53ue(...)
_64etuvsbptod=(_humiwavqej4w[1]~_humiwavqej4w[5]);
return ((_humiwavqej4w[6]~_humiwavqej4w[18])+2*(_humiwavqej4w[6]&_humiwavqej4w[18]));
end;
_e6me00viib8f[((_humiwavqej4w[19]~_humiwavqej4w[20])+2*(_humiwavqej4w[19]&_humiwavqej4w[20]))]=_8gldk1nc53ue;
local function _vondrwe9jp3q(...)
return _r4anxvrj94nr;
end;
_e6me00viib8f[(((((_humiwavqej4w[7]+_humiwavqej4w[14])+_humiwavqej4w[11])-_humiwavqej4w[12])+_humiwavqej4w[16]))]=_vondrwe9jp3q;
local function _tdh8oronxzq8(...)
local _kfxxudpr8ubs=(_humiwavqej4w[22]~_humiwavqej4w[15]);
return (((((_humiwavqej4w[21]+_humiwavqej4w[26])-_humiwavqej4w[10])+_humiwavqej4w[2])+_humiwavqej4w[4]));
end;
_e6me00viib8f[((_humiwavqej4w[24]~_humiwavqej4w[23])+2*(_humiwavqej4w[24]&_humiwavqej4w[23]))]=_tdh8oronxzq8;
local _ftuuc9yg5bkv={[(_humiwavqej4w[9]~_humiwavqej4w[3])]=true};
local _163972fi826t=((_humiwavqej4w[27]~_humiwavqej4w[17])+2*(_humiwavqej4w[27]&_humiwavqej4w[17]));
while _163972fi826t~=((_humiwavqej4w[13]|_humiwavqej4w[13])+(_humiwavqej4w[13]&_humiwavqej4w[13])) and(_163972fi826t+(_humiwavqej4w[25]~_humiwavqej4w[8])-50667==_163972fi826t) do
local _6la45bnbu7wx,_7k32leodaic8=_e6me00viib8f[_163972fi826t]();
if _6la45bnbu7wx==_r4anxvrj94nr then
_rrq07jhrmoq1=true;
break;
end;
_163972fi826t=_6la45bnbu7wx;
end;
if _rrq07jhrmoq1 then
break;
end;
end;
return setmetatable({},{[_qvi1qabcym3d[1]]=function()print(_qvi1qabcym3d[2])end});
end;
do
local _aih9bes7pt2l <close> =_rwl4gek1oljp();
print(_qvi1qabcym3d[3]);
end;
print(_qvi1qabcym3d[4]);
