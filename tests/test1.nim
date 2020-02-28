import unittest

import libclang_porcelain
import libclang_bindings/index

import os
var i = createIndex(false,false)
let tu = parseTranslationUnit(i,some(paramStr(1)),@[],@[])
var c = getCursor(tu.get).get

var cs : seq[CXCursor]
proc visitor (cursor:CXCursor,parent:CXCursor,client_data:CXClientData):CXChildVisitResult =
  echo cursor.kind
  cs.add(cursor)
  result = CXChildVisit_Recurse
  echo clang_visitChildren(c, visitor, nil.CXClientData).ord
  echo cs.len

test "correct welcome":
  let a = Index(foobar: "hello world")
  echo a.foobar
  check getWelcomeMessage() == "Hello, World!"
