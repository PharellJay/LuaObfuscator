local _kynl5xnb=0;
local _w9wdktwb=0;
local function _d67swudr(_wj8wqw29,_2dah7w2h)
if _wj8wqw29 then
_kynl5xnb=_kynl5xnb+1;
print("PASS: ".._2dah7w2h);
else
_w9wdktwb=_w9wdktwb+1;
print("FAIL: ".._2dah7w2h);
end;
end;
_d67swudr(true==true,"boolean true");
_d67swudr(false==false,"boolean false");
_d67swudr(not false,"not false");
_d67swudr(not not true,"double not");
_d67swudr(nil==nil,"nil equality");
_d67swudr(type(nil)=="nil","type(nil)");
_d67swudr(type(true)=="boolean","type(boolean)");
_d67swudr(type(42)=="number","type(number)");
_d67swudr(type("hi")=="string","type(string)");
_d67swudr(type({})=="table","type(table)");
_d67swudr(type(print)=="function","type(function)");
_d67swudr(42==42,"integer");
_d67swudr(3.14==3.14,"float");
_d67swudr(0==0,"zero");
_d67swudr(-1==-1,"negative");
_d67swudr(1e3==1000,"scientific notation");
_d67swudr(0xff==255,"hex literal");
_d67swudr(0x1A==26,"hex literal uppercase");
_d67swudr(0.5+0.5==1,"float addition");
_d67swudr(0.1+0.2~=0.3,"float imprecision");
_d67swudr(1/2==0.5,"division");
_d67swudr(2+3==5,"addition");
_d67swudr(10-4==6,"subtraction");
_d67swudr(3*7==21,"multiplication");
_d67swudr(15/3==5,"division");
_d67swudr(17%5==2,"modulo");
_d67swudr(2^10==1024,"exponentiation");
_d67swudr(-(3)==-3,"unary minus");
_d67swudr(5==5,"equal");
_d67swudr(5~=6,"not equal");
_d67swudr(5<10,"less than");
_d67swudr(10>5,"greater than");
_d67swudr(5<=5,"less equal");
_d67swudr(5>=5,"greater equal");
_d67swudr(true and true,"and true");
_d67swudr(not(true and false),"and false");
_d67swudr(true or false,"or true");
_d67swudr(not(false or false),"or false");
_d67swudr("a" and "b"=="b","and returns last");
_d67swudr(false or "c"=="c","or returns fallback");
_d67swudr(nil or "d"=="d","nil or default");
_d67swudr(#"hello"==5,"string length (double quotes)");
_d67swudr(#'hello'==5,"string length (single quotes)");
local _kftg37hp="Hello";
local _64thofja="World";
_d67swudr(_kftg37hp.." ".._64thofja=="Hello World","concatenation");
_d67swudr(("  trim  "):match("^%s*(.-)%s*$")=="trim","string match");
_d67swudr(("abc"):upper()=="ABC","string.upper");
_d67swudr(("ABC"):lower()=="abc","string.lower");
_d67swudr(("a,b,c"):find(",")==2,"string.find");
_d67swudr(("hello"):sub(1,2)=="he","string.sub");
_d67swudr(("  a  "):match("^%s*(.-)%s*$")=="a","string.match with captures");
_d67swudr(tostring(123)=="123","tostring");
local _pix54q5x=1;
_d67swudr(_pix54q5x==1,"local variable");
do
local _t65rsyy3=2;
_d67swudr(_t65rsyy3==2,"local shadowing inner");
end;
_d67swudr(_pix54q5x==1,"local shadowing outer restored");
local _4i9xfhdc,_bxkp2tqi=10,20;
_d67swudr(_4i9xfhdc==10 and _bxkp2tqi==20,"multiple assignment");
_4i9xfhdc,_bxkp2tqi=_bxkp2tqi,_4i9xfhdc;
_d67swudr(_4i9xfhdc==20 and _bxkp2tqi==10,"swap");
local _2dexu9ke;
if false then
_2dexu9ke="wrong";
elseif false then
_2dexu9ke="also wrong";
else
_2dexu9ke="correct";
end;
_d67swudr(_2dexu9ke=="correct","if-elseif-else");
if true then
_2dexu9ke="taken";
end;
_d67swudr(_2dexu9ke=="taken","if true");
local _5gvo4khy;
if true then
if false then
_5gvo4khy="bad";
else
_5gvo4khy="good";
end;
end;
_d67swudr(_5gvo4khy=="good","nested if");
local _sgmyoq1p=0;
while _sgmyoq1p<3 do
_sgmyoq1p=_sgmyoq1p+1;
end;
_d67swudr(_sgmyoq1p==3,"while loop");
local _db46vlen=0;
while true do
_db46vlen=_db46vlen+1;
if _db46vlen>=3 then
break;
end;
end;
_d67swudr(_db46vlen==3,"while with break");
local _pia9ilee=0;
repeat
_pia9ilee=_pia9ilee+1;
until _pia9ilee==3;
_d67swudr(_pia9ilee==3,"repeat until");
local _rzsma0at=0;
for _6nhk3906=1,5 do
_rzsma0at=_rzsma0at+_6nhk3906;
end;
_d67swudr(_rzsma0at==15,"numeric for 1..5");
_rzsma0at=0;
for _bv3w67al=1,10,2 do
_rzsma0at=_rzsma0at+_bv3w67al;
end;
_d67swudr(_rzsma0at==25,"numeric for step 2");
local _gblomps4=0;
for _fbgf1hyy=1,100 do
_gblomps4=_gblomps4+1;
if _fbgf1hyy==5 then
break;
end;
end;
_d67swudr(_gblomps4==5,"for with break");
local _u69o5zl6={"a","b","c"};
local _kethctsi={};
for _u3x7if1n in ipairs(_u69o5zl6) do
_kethctsi[#_kethctsi+1]=_u3x7if1n;
end;
_d67swudr(_kethctsi[1]==1 and _kethctsi[2]==2 and _kethctsi[3]==3,"ipairs");
local _h8t8fhx0={["x"]=1,["y"]=2};
local _dwf8mq5w={};
for _vo4x7m5s,_fspoyh26 in pairs(_h8t8fhx0) do
_dwf8mq5w[_vo4x7m5s]=_fspoyh26;
end;
_d67swudr(_dwf8mq5w["x"]==1 and _dwf8mq5w["y"]==2,"pairs");
local _fl4ltrcw={};
_d67swudr(_fl4ltrcw[1]==nil,"empty table index");
_fl4ltrcw[1]=10;
_fl4ltrcw[2]=20;
_d67swudr(_fl4ltrcw[1]==10 and _fl4ltrcw[2]==20,"table assignment");
local _ehvqyrdj={1,2,3,4,5};
_d67swudr(#_ehvqyrdj==5,"table length");
local _5763j2mp={["a"]=1,["b"]=2};
_d67swudr(_5763j2mp["a"]==1 and _5763j2mp["b"]==2,"table map syntax");
_d67swudr(_5763j2mp["a"]==1,"table bracket index");
local _l14a9x6f={[1]="one",[2]="two"};
_d67swudr(_l14a9x6f[2]=="two","table computed key");
local _91rsjtfn={1,2,nil,4};
_d67swudr(#_91rsjtfn==4 or#_91rsjtfn==2,"table with holes (unspecified behavior)");
local _114qi7zd={1,2,3};
_114qi7zd[#_114qi7zd+1]=4;
_d67swudr(#_114qi7zd==4,"table append");
local _5w7epju0={};
for _bp1bcxgb=1,100 do
_5w7epju0[_bp1bcxgb]=_bp1bcxgb;
end;
_d67swudr(#_5w7epju0==100,"large sequential table");
local _pxuyhzc9={{["a"]={["b"]="deep"}}};
_d67swudr(_pxuyhzc9[1]["a"]["b"]=="deep","nested table access");
local _q7py4f2z={[true]="bool",[42]="num",["k"]="str"};
_d67swudr(_q7py4f2z[true]=="bool","table boolean key");
_d67swudr(_q7py4f2z[42]=="num","table number key");
_d67swudr(_q7py4f2z["k"]=="str","table string key");
function add(_104g9p7b,_5yc7mi91)
return _104g9p7b+_5yc7mi91;
end;
_d67swudr(add(3,4)==7,"global function");
local function sub(_6uqdjtdz,_qsolxhbp)
return _6uqdjtdz-_qsolxhbp;
end;
_d67swudr(sub(10,3)==7,"local function");
local function _a8yupszm()
return 1,2,3;
end;
local _75v7lt9g,_hbeukemh,_y2l8mox2=_a8yupszm();
_d67swudr(_75v7lt9g==1 and _hbeukemh==2 and _y2l8mox2==3,"multiple returns");
local function _cpfdg7t0(_6cduke9h)
if _6cduke9h<0 then
return -1;
end;
return _6cduke9h;
end;
_d67swudr(_cpfdg7t0(-5)==-1,"early return");
_d67swudr(_cpfdg7t0(5)==5,"normal return after early");
local function _gnseritu(...)
local _avfmeetm={...};
return #_avfmeetm;
end;
_d67swudr(_gnseritu(1,2,3)==3,"varargs count");
_d67swudr(_gnseritu()==0,"varargs empty");
local _gx6r2jyr=function(_75v7lt9g)return _75v7lt9g*2 end;
_d67swudr(_gx6r2jyr(5)==10,"anonymous function");
local function _fqd2bhkb()
local _capoodhl=0;
return function()_capoodhl=_capoodhl+1 return _capoodhl end;
end;
local _fk5pp5xq=_fqd2bhkb();
_d67swudr(_fk5pp5xq()==1,"closure first call");
_d67swudr(_fk5pp5xq()==2,"closure second call");
_d67swudr(_fk5pp5xq()==3,"closure third call");
local function _f8wurl7t(_q32v8m7f)
if _q32v8m7f<=1 then
return 1;
end;
return _q32v8m7f*_f8wurl7t(_q32v8m7f-1);
end;
_d67swudr(_f8wurl7t(5)==120,"recursion");
local function _0cw7agxg(_a4w2dljf,_myu011c7)
if _a4w2dljf==0 then
return _myu011c7;
end;
return _0cw7agxg(_a4w2dljf-1,_myu011c7*_a4w2dljf);
end;
_d67swudr(_0cw7agxg(5,1)==120,"tail recursion");
local _c8nr3b8k={["value"]=42};
function _c8nr3b8k:get()
return self["value"];
end;
_d67swudr(_c8nr3b8k:get()==42,"method call colon syntax");
_d67swudr(_c8nr3b8k["get"](_c8nr3b8k)==42,"method call dot syntax");
local _5153d39d,_xw518f7k=pcall(function()error("test error")end);
_d67swudr(not _5153d39d,"pcall catches error");
_d67swudr(tostring(_xw518f7k):find("test error")~=nil,"pcall error message");
local _4ravictl,_a62481e3=pcall(function()return "success" end);
_d67swudr(_4ravictl and _a62481e3=="success","pcall success");
local _saxv3wyq=0;
do
goto skip;
_saxv3wyq=100;
::skip::;
_saxv3wyq=200;
end;
_d67swudr(_saxv3wyq==200,"goto forward");
local _iuigzfqt=0;
do
::loop::;
_iuigzfqt=_iuigzfqt+1;
if _iuigzfqt<3 then
goto loop;
end;
end;
_d67swudr(_iuigzfqt==3,"goto backward (loop)");
_d67swudr(10+"20"==30,"string to number coercion");
_d67swudr(10 .. 20=="1020","number to string coercion");
_d67swudr("hello".. 42=="hello42","concat number to string");
local _wrf5uzgv=0;
local function _tgkap3vu()
_wrf5uzgv=_wrf5uzgv+1;
return true;
end;
local _w9pu0uoj=false and _tgkap3vu();
_d67swudr(_wrf5uzgv==0,"short-circuit and (left false)");
_w9pu0uoj=true or _tgkap3vu();
_d67swudr(_wrf5uzgv==0,"short-circuit or (left true)");
_w9pu0uoj=true and _tgkap3vu();
_d67swudr(_wrf5uzgv==1,"short-circuit and evaluates right when needed");
_d67swudr(#""==0,"empty string length");
_d67swudr(#"a"==1,"single char string length");
_d67swudr(#"\000"==1,"null byte string length");
_d67swudr(#"hello world"==11,"multi char string length");
_d67swudr((1+2)*(3+4)==21,"nested arithmetic with parens");
_d67swudr(2^3^2==512,"exponentiation associativity (right)");
_d67swudr(not(false or false)==true,"complex boolean");
_d67swudr(1<2 and 2<3 and 3<4,"chained comparisons");
local _ub4nyt47={3,1,4,1,5,9};
table["sort"](_ub4nyt47);
_d67swudr(_ub4nyt47[1]==1 and _ub4nyt47[#_ub4nyt47]==9,"table.sort");
local _ece3hvn4=table["concat"]({"a","b","c"},",");
_d67swudr(_ece3hvn4=="a,b,c","table.concat");
local _ct0wi6h4={10,20,30};
table["insert"](_ct0wi6h4,40);
_d67swudr(_ct0wi6h4[4]==40,"table.insert");
table["remove"](_ct0wi6h4,1);
_d67swudr(_ct0wi6h4[1]==20 and#_ct0wi6h4==3,"table.remove");
_d67swudr(math["abs"](-5)==5,"math.abs");
_d67swudr(math["floor"](3.9)==3,"math.floor");
_d67swudr(math["ceil"](3.1)==4,"math.ceil");
_d67swudr(math["max"](1,5,3)==5,"math.max");
_d67swudr(math["min"](1,5,3)==1,"math.min");
_d67swudr(math["sqrt"](9)==3,"math.sqrt");
_d67swudr(math["sin"](0)==0,"math.sin");
_d67swudr(math["cos"](0)==1,"math.cos");
local _6xpxh361={["a"]=1,["b"]=2};
_6xpxh361["c"]=_6xpxh361["a"]+_6xpxh361["b"];
_d67swudr(_6xpxh361["c"]==3,"self-referencing table");
local _51ful9rp={};
local _bvijgwdi=_51ful9rp;
for _g35p0djw=1,20 do
_bvijgwdi["child"]={};
_bvijgwdi=_bvijgwdi["child"];
end;
_bvijgwdi["value"]="found";
_bvijgwdi=_51ful9rp;
for _1zk8tg0o=1,20 do
_bvijgwdi=_bvijgwdi["child"];
end;
_d67swudr(_bvijgwdi["value"]=="found","deep table nesting (20 levels)");
local _859j4qy6="";
for _b7fiujr0=1,3 do
for _dmf3qpqh=1,3 do
if _b7fiujr0==2 and _dmf3qpqh==2 then
break;
end;
_859j4qy6=_859j4qy6.._b7fiujr0.._dmf3qpqh.." ";
end;
if _b7fiujr0==2 then
break;
end;
end;
_d67swudr(_859j4qy6=="11 12 13 21 ","nested loops with break");
_d67swudr("\n"~="a","newline escape");
_d67swudr("\t"=="\t","tab escape");
_d67swudr("\\"=="\\","backslash escape");
_d67swudr("\""=='"',"double quote escape");
_d67swudr("'"=="'","single quote");
_d67swudr("\101"=="e","decimal escape");
_d67swudr(string["char"](0x45)=="E","hex via string.char");
_d67swudr(("hello\nworld"):find("\n")~=nil,"newline in string");
_d67swudr((0 and "zero is truthy")=="zero is truthy","0 is truthy");
_d67swudr(("" and "empty string is truthy")=="empty string is truthy","empty string is truthy");
_d67swudr((nil or "nil is falsy")=="nil is falsy","nil is falsy");
_d67swudr((false or "false is falsy")=="false is falsy","false is falsy");
local _e1gy86d6={1,2,3,4,5};
local _1cfvs4ru=0;
for _1x2m6jc9,_wi3dxkk2 in ipairs(_e1gy86d6) do
_1cfvs4ru=_1cfvs4ru+_wi3dxkk2;
end;
_d67swudr(_1cfvs4ru==15,"ipairs sum");
_d67swudr(select("#",1,2,3)==3,"select #");
_d67swudr(select(2,"a","b","c")=="b","select index");
_d67swudr(("hello"):rep(0)=="","string.rep 0");
_d67swudr(("ab"):rep(3)=="ababab","string.rep 3");
_d67swudr(("hello"):byte(1)==104,"string.byte");
_d67swudr(string["char"](104,101,108,108,111)=="hello","string.char");
_d67swudr(("  hello  "):match("^%s*(.-)%s*$")=="hello","string.trim via match");
print("────────────────────────────");
print("Tests: "..(_kynl5xnb+_w9wdktwb).." | PASS: ".._kynl5xnb.." | FAIL: ".._w9wdktwb);
if _w9wdktwb>0 then
error("Some tests FAILED");
end;
