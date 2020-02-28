import libclang_bindings/[index,cxstring,cxerrorcode]
import macros, sequtils, bitops, std/time_t, system, options, tables, sugar, sets
import stew/[result,ptrops]

const allGlobalOptFlags* = @[
  CXGlobalOpt_None,
  CXGlobalOpt_ThreadBackgroundPriorityForIndexing,
  CXGlobalOpt_ThreadBackgroundPriorityForEditing,
  CXGlobalOpt_ThreadBackgroundPriorityForAll
]

const allCXDiagnosticDisplayOptions* = @[
  CXDiagnostic_DisplaySourceLocation,
  CXDiagnostic_DisplayColumn,
  CXDiagnostic_DisplaySourceRanges,
  CXDiagnostic_DisplayOption,
  CXDiagnostic_DisplayCategoryId,
  CXDiagnostic_DisplayCategoryName
]

const allCXTranslationUnit_Flags* = @([
  CXTranslationUnit_None,
  CXTranslationUnit_DetailedPreprocessingRecord,
  CXTranslationUnit_Incomplete,
  CXTranslationUnit_PrecompiledPreamble,
  CXTranslationUnit_CacheCompletionResults,
  CXTranslationUnit_ForSerialization,
  CXTranslationUnit_CXXChainedPCH,
  CXTranslationUnit_SkipFunctionBodies,
  CXTranslationUnit_IncludeBriefCommentsInCodeCompletion,
  CXTranslationUnit_CreatePreambleOnFirstParse,
  CXTranslationUnit_KeepGoing,
  CXTranslationUnit_SingleFileParse,
  CXTranslationUnit_LimitSkipFunctionBodiesToPreamble,
  CXTranslationUnit_IncludeAttributedTypes,
  CXTranslationUnit_VisitImplicitAttributes,
  CXTranslationUnit_IgnoreNonErrorsFromIncludedFiles,
])

type
  FileUniqueId* = object
    deviceId*: culonglong
    fileId*: culonglong
    modificationTime*: Time
  File* = object
    `ptr`*:CXFile
    name*: string
    uniqueId*: Option[FileUniqueId]
    time*: Time
  TUResourceUsage* = object
    `ptr`*:CXTUResourceUsage
    entries*: Table[CXTUResourceUsageKind,culonglong]
  TargetInfo* = object
    triple*: string
    pointerWidth*: cint
  TranslationUnit* = object
    `ptr`*: CXTranslationUnit
    resourceUsage*: TUResourceUsage
    targetInfo*: Option[TargetInfo]
  Index* = object
    `ptr`*: CXIndex
    tus*: seq[TranslationUnit]
  FileLocation* = object
    file*: File
    line*: Natural
    column*: Natural
    offset*: Natural
  SourceRangeList* = object
    `ptr`*: ptr CXSourceRangeList
    ranges*: seq[ptr CXSourceRange]
  DiagnosticCategory* = object
    number*: cuint
    name*: string
    text*: string
  Diagnostic* = object
    severity*: CXDiagnosticSeverity
    location*: CXSourceLocation
    spelling*: string
    option*: (string,string)
    category*: DiagnosticCategory
    fixits*: seq[(string,ptr CXSourceRange)]
    children*: Diagnostics
  Diagnostics* = object
    `ptr`*:CXDiagnosticSet
    diagnostics*: seq[Diagnostic]

proc `=destroy`*(ds: var Diagnostics) =
  clang_disposeDiagnosticSet(ds.`ptr`)
proc `=destroy`*(i:var Index) =
  ## clang_disposeIndex
  for t in i.tus:
    clang_disposeCXTUResourceUsage(t.resourceUsage.`ptr`)
    clang_disposeTranslationUnit(t.`ptr`)
  clang_disposeIndex(i.`ptr`)
proc `=destroy`*(ranges: var SourceRangeList) =
  if  not (isNil (ranges.`ptr`)): clang_disposeSourceRangeList(ranges.`ptr`)

proc breakupFlags[T:enum](options:cuint,members:seq[T]):seq[T] =
  if options == 0:
    @[low(T)]
  else:
    members[1..^1].filterIt(bitand((cuint)it,options) == (cuint)it)

proc combineFlags[T:enum](options:seq[T]):cuint =
  for o in options:
    result = bitor(result,(cuint)ord(o))

proc toNimString(cxString: sink CXString):string =
  result = $clang_getCString(cxString)
  clang_disposeString(cxString)

proc toNimStrings(cxStringSet: ptr CXStringSet): seq[string] =
  if (isNil cxStringSet):
    result = @[]
  else:
    let cxStrings: seq[CXString] = toSeq(cxStringSet[].Strings.toOpenArray(0,cxStringSet[].Count-1))
    result = cxStrings.mapIt($ clang_getCString(it))
    clang_disposeStringSet cxStringSet

proc createIndex*(excludeDeclarationsFromPCH: bool, displayDiagnostics: bool): Index =
  ## clang_createIndex(
  Index(`ptr`:clang_createIndex(excludeDeclarationsFromPCH.ord.cint, displayDiagnostics.ord.cint))

proc `globalOpts=`*(i:Index,opts:seq[CXGlobalOptFlags]) =
  ## clang_CXIndex_setGlobalOptions
  clang_CXIndex_setGlobalOptions(i.`ptr`,combineFlags(opts))

proc globalOpts*(i:Index):seq[CXGlobalOptFlags] =
  ## clang_CXIndex_getGlobalOptions
  breakupFlags clang_CXIndex_getGlobalOptions(i.`ptr`),allGlobalOptFlags

proc isMultipleIncludeGuarded*(tu: TranslationUnit, file: File):bool =
  ## clang_isFileMultipleIncludeGuarded
  clang_isFileMultipleIncludeGuarded(tu.`ptr`,file.`ptr`) == 0

proc uniqueId(f:CXFile): Option[FileUniqueId] =
  ## clang_getFileUniqueID
  var p = cast[ptr CXFileUniqueID](alloc0(sizeof(CXFileUniqueId)))
  let res = clang_getFileUniqueID(f,p)
  if res == 0:
    result = some(FileUniqueId(deviceId: p[][0], fileId: p[][1], modificationTime: (Time)p[][2]))
    dealloc(p)

proc name(f:CXFile):string =
  ## clang_getFileName
  ## clang_File_tryGetRealPathName
  result = clang_File_tryGetRealPathName(f).toNimString
  if result.len == 0:
    result = clang_getFileName(f).toNimString

proc time(f:CXFile):Time =
  ## clang_getFileTime
  clang_getFileTime(f)

proc fillOutFile(f:CXFile):File =
  File(
    `ptr`:f,
    name: f.name(),
    time: f.time(),
    uniqueId: f.uniqueId()
  )

proc getContents*(tu: TranslationUnit, file: File): Option[string] =
  ## clang_getFileContents
  var p = cast[ptr csize_t](alloc0(sizeof(csize_t)))
  let res = clang_getFileContents(tu.`ptr`,file.`ptr`,p)
  if (not (isNil p)):
    result = some($res)
    dealloc(p)

proc getFile*(tu: TranslationUnit, fileName: string): Option[File] =
  ## clang_getFile
  let res = clang_getFile(tu.`ptr`, $fileName)
  if (not (isNil cast[pointer](res))):
    result = some(fillOutFile(res))

proc nullLocation*():CXSourceLocation =
  clang_getNullLocation()

proc `==`*(s1:CXSourceLocation,s2:CXSourceLocation):bool =
  clang_equalLocations(s1,s2) != 0

proc getLocation*(tu:TranslationUnit, fl:FileLocation): CXSourceLocation =
  ## clang_getLocation
  clang_getLocation(tu.`ptr`,fl.file.`ptr`,(cuint)fl.line,(cuint)fl.column)

proc getLocationForOffset*(tu: TranslationUnit, f: File, offset: Natural):CXSourceLocation =
  ## clang_getLocationForOffset
  clang_getLocationForOffset(tu.`ptr`,f.`ptr`,(cuint)offset)

proc isInSystemHeader*(l:CXSourceLocation):bool =
  ## clang_Location_isInSystemHeader
  clang_Location_isInSystemHeader(l) != 0

proc isFromMainFile*(l: CXSourceLocation):bool =
  ## clang_Location_isFromMainFile
  clang_Location_isFromMainFile(l) != 0

proc nullRange*():CXSourceRange = clang_getNullRange()

proc `==`*(r1:CXSourceRange,r2:CXSourceRange):bool =
  clang_equalRanges(r1,r2) != 0

proc isNull*(r:CXSourceRange):bool =
  clang_Range_isNull(r) != 0

template extractLocation(l:untyped, f:untyped): untyped  =
  var file = cast[ptr CXFile](alloc0(sizeof(CXFile)))
  var line = cast[ptr cuint](alloc0(sizeof(cuint)))
  var column  = cast[ptr cuint](alloc0(sizeof(cuint)))
  var offset  = cast[ptr cuint](alloc0(sizeof(cuint)))
  f(l,file,line,column,offset)
  if not (isNil file):
    result = some(FileLocation(file: fillOutFile(file[]),
                               line: (Natural)line[],
                               column: (Natural)column[],
                               offset: (Natural)offset[]))

proc getExpansionLocation*(l:CXSourceLocation):Option[FileLocation] =
  extractLocation(l, clang_getExpansionLocation)
proc getInstantiationLocation*(l:CXSourceLocation):Option[FileLocation] =
  extractLocation(l, clang_getInstantiationLocation)
proc getSpellingLocation*(l:CXSourceLocation):Option[FileLocation] =
  extractLocation(l, clang_getSpellingLocation)
proc getFileLocation*(l:CXSourceLocation):Option[FileLocation] =
  extractLocation(l, clang_getFileLocation)
proc getRangeStart*(r:CXSourceRange):CXSourceLocation =
  clang_getRangeStart(r)
proc getRangeEnd*(r:CXSourceRange):CXSourceLocation =
  clang_getRangeEnd(r)

proc rangelistToSeq(p: ptr CXSourceRangeList):SourceRangeList =
  if not (isNil p):
    var rs : seq[ptr CXSourceRange]
    for r in 0..(int)p[].count-1:
      rs.add p[].ranges.offset r
    result = SourceRangeList(ranges:rs,`ptr`:p)

proc getSkippedRanges*(tu:TranslationUnit, f:File):SourceRangeList =
  clang_getSkippedRanges(tu.`ptr`,f.`ptr`).rangeListToSeq

proc getAllSkippedRanges*(tu:TranslationUnit):SourceRangeList =
  clang_getAllSkippedRanges(tu.`ptr`).rangeListToSeq

proc getDiagnosticsHelper[T:CXTranslationUnit|CXDiagnostic](diagnosticContainer: T):Diagnostics

proc fillOutDiagnostic(d:CXDiagnostic):Diagnostic =
  var fixits : seq[(string,ptr CXSourceRange)]
  for f in 0..clang_getDiagnosticNumFixIts(d)-1:
    let srPtr = cast[ptr CXSourceRange](alloc0(sizeof(CXSourceRange)))
    let fixString = clang_getDiagnosticFixIt(d,(cuint)f,srPtr).toNimString
    fixits.add((fixString, srPtr))
  let dc =
    block:
      let dcnumber = clang_getDiagnosticCategory(d)
      DiagnosticCategory(
        number: dcnumber,
        name: clang_getDiagnosticCategoryName(dcnumber).toNimString,
        text: clang_getDiagnosticCategoryText(d).toNimString
      )
  let disableOptPtr = cast[ptr CXString](alloc0(sizeof(CXString)))
  disableOptPtr[] = CXString()
  let opt = clang_getDiagnosticOption(d,disableOptPtr)
  Diagnostic(
    severity: clang_getDiagnosticSeverity(d),
    location: clang_getDiagnosticLocation(d),
    option: (opt.toNimString, disableOptPtr[].toNimString),
    category: dc,
    fixits: fixits,
    children: getDiagnosticsHelper(d)
  )

proc getDiagnosticsHelper[T:CXTranslationUnit|CXDiagnostic](diagnosticContainer: T):Diagnostics =
  when T is CXTranslationUnit:
    let ds = clang_getDiagnosticSetFromTU(diagnosticContainer)
  else:
    let ds = clang_getChildDiagnostics(diagnosticContainer)
  let count = clang_getNumDiagnosticsInSet(ds)
  result.`ptr` = ds
  if count > 0:
    for i in 0 .. count-1:
      let d = clang_getDiagnosticInSet(ds,i)
      result.diagnostics.add(fillOutDiagnostic(d))

proc getDiagnostics*(tu:TranslationUnit):Diagnostics =
  getDiagnosticsHelper(tu.`ptr`)

proc getTUResourceUsage(tu : TranslationUnit):TUResourceUsage =
  let ru = clang_getCXTUResourceUsage(tu.`ptr`)
  let entries = @(toOpenArray(cast[ptr UncheckedArray[CXTUResourceUsageEntry]](ru.entries), 0, (int)ru.numEntries-1))
  var table : Table[CXTUResourceUsageKind, culonglong]
  for e in entries:
    table.add(e.kind,e.amount)
  result = TUResourceUsage(
    `ptr` : ru,
    entries: table
  )

proc fillOutTranslationUnit(tu: var TranslationUnit) =
  tu.resourceUsage = getTUResourceUsage(tu)
  tu.targetInfo =
      clang_getTranslationUnitTargetInfo(tu.`ptr`).option.map((ti: CXTargetInfo) => (
        defer: ti.clang_TargetInfo_dispose;
        result = TargetInfo(triple: clang_TargetInfo_getTriple(ti).toNimString,
                            pointerWidth: ti.clang_TargetInfo_getPointerWidth);))

proc createTranslationUnitFromSourceFile*(i: var Index, sourceFilename: Option[string], commandLineArguments:seq[string]): Option[TranslationUnit] =
  var cliPtr = cast[ptr cstring](allocCStringArray commandLineArguments)
  var sfPtr = sourceFilename.get("").cstring
  var unsavedPtr : ptr CXUnsavedFile
  let tu = clang_createTranslationUnitFromSourceFile(i.`ptr`,sfPtr,(cint)commandLineArguments.len,cliPtr,(cuint)0,unsavedPtr)
  if tu.pointer != nil:
    let res = TranslationUnit(`ptr`:tu)
    i.tus.add(res)
    result = some(res)

proc parseTranslationUnit*(i: var Index, sourceFilename: Option[string], commandLineArguments:seq[string], options:seq[CXTranslationUnit_Flags]): Option[TranslationUnit] =
  var cliPtr = cast[ptr cstring](allocCStringArray commandLineArguments)
  var sfPtr = sourceFilename.get("").cstring
  var unsavedPtr : ptr CXUnsavedFile
  var tx = cast[ptr CXTranslationUnit](alloc0(sizeof(CXTranslationUnit)))
  let res : CXErrorCode = clang_parseTranslationUnit2(i.`ptr`,sfPtr,cliPtr,(cint)commandLineArguments.len,unsavedPtr,(cuint)0,combineFlags(options),tx)
  case res
  of CXError_Success:
    var tu = TranslationUnit(`ptr`:tx[])
    fillOutTranslationUnit(tu)
    i.tus.add(tu)
    result = some(tu)
  else: result = none(TranslationUnit)

proc reparseTranslationUnit*(tu: var TranslationUnit,options:seq[CXTranslationUnit_Flags]): Result[TranslationUnit,CXErrorCode] =
  var p : ptr CXUnsavedFile
  let res = clang_reparseTranslationUnit(tu.`ptr`,(cuint)0,p,combineFlags(options))
  case res
  of CXError_Success:
    var tu = tu
    tu.fillOutTranslationUnit
    result = ok(tu)
  else: result = err(res)

proc getCursor*(tu: TranslationUnit):Option[CXCursor] =
  let c = clang_getTranslationUnitCursor(tu.`ptr`)
  let k = clang_getCursorKind(c)
  if clang_Cursor_isNull(c) == 0 and (clang_isInvalid(k) == 0):
    result = some(c)
