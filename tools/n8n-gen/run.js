const fs=require('fs');
const stub=function(o){return {o:o,to:function(){return this},onCase:function(){return this},onTrue:function(){return this},onFalse:function(){return this},add:function(){return this}}};
const node=stub,trigger=stub,switchCase=stub,ifElse=stub,expr=function(s){return s};
const workflow=function(){return stub({})};
const src=fs.readFileSync('chk.js','utf8');
eval(src);
console.log('syntax ok');
