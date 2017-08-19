module Language.Swift
    ( renderer
    ) where

import Doc
import IRGraph
import Prelude

import Data.Array as A
import Data.Char.Unicode (isAlphaNum, isDigit)
import Data.Foldable (for_)
import Data.FoldableWithIndex (forWithIndex_)
import Data.Map (Map)
import Data.Map as M
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.String.Util (camelCase, capitalize, legalizeCharacters, startWithLetter, stringEscape)
import Data.Tuple (Tuple(..))
import Utils (removeElement)

keywords :: Array String
keywords =
    [ "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "static", "struct", "subscript", "typealias", "var"
    , "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while"
    , "as", "Any", "catch", "false", "is", "nil", "rethrows", "super", "self", "Self", "throw", "throws", "true", "try"
    , "_"
    , "associativity", "convenience", "dynamic", "didSet", "final", "get", "infix", "indirect", "lazy", "left", "mutating", "none", "nonmutating", "optional", "override", "postfix", "precedence", "prefix", "Protocol", "required", "right", "set", "Type", "unowned", "weak", "willSet"
    , "String", "Int", "Double", "Bool"
    , "checkNull", "convertArray", "convertOptional", "convertDict"
    ]

renderer :: Renderer
renderer =
    { name: "Swift"
    , aceMode: "swift"
    , extension: "swift"
    , doc: swiftDoc
    , transforms:
        { nameForClass: simpleNamer nameForClass
        , nextName: \s -> "Other" <> s
        , forbiddenNames: keywords
        , topLevelName: noForbidNamer (swiftNameStyle true)
        , unions: Just
            { predicate: unionIsNotSimpleNullable
            , properName: simpleNamer (swiftNameStyle true <<< combineNames)
            , nameFromTypes: simpleNamer (unionNameIntercalated (swiftNameStyle true) "Or")
            }
        }
    }

swiftNameStyle :: Boolean -> String -> String
swiftNameStyle isUpper =
    legalizeCharacters isPartCharacter >>> camelCase >>> startWithLetter isStartCharacter isUpper
    where
        isStartCharacter :: Char -> Boolean
        isStartCharacter c = c == '_' || (isAlphaNum c && not (isDigit c))

        isPartCharacter :: Char -> Boolean
        isPartCharacter c = c == '_' || isAlphaNum c

nameForClass :: IRClassData -> String
nameForClass (IRClassData { names }) = swiftNameStyle true $ combineNames names

swiftDoc :: Doc Unit
swiftDoc = do
    line "import Foundation"
    forEachClass_ \className properties -> do
        blank
        renderClassDefinition className properties
    forEachUnion_ \unionName unionTypes -> do
        blank
        renderUnionDefinition unionName unionTypes
    blank
    line """func convertArray<T>(converter: (Any) -> T?, json: Any) -> [T]? {
    guard let jsonArr = json as? [Any] else { return nil }
    var arr: [T] = []
    for v in jsonArr {
        if let converted = converter(v) {
            arr.append(converted)
        } else {
            return nil
        }
    }
    return arr
}

func convertOptional<T>(converter: (Any) -> T?, json: Any?) -> T? {
    guard let v = json
    else {
        return nil
    }
    return converter(v)
}

func convertDict<T>(converter: (Any) -> T?, json: Any?) -> [String: T]? {
    guard let jsonDict = json as? [String: Any] else { return nil }
    var dict: [String: T] = [:]
    for (k, v) in jsonDict {
        if let converted = converter(v) {
            dict[k] = converted
        } else {
            return nil
        }
    }
    return dict
}

func convertDouble(_ v: Any) -> Double? {
    if let i = v as? Int {
        return Double(i)
    }
    if let d = v as? Double {
        return d
    }
    return nil
}

func removeNSNull(_ v: Any?) -> Any? {
    if let w = v {
        if w is NSNull {
            return nil
        }
        return w
    }
    return nil
}

func checkNull(_ v: Any?) -> Any?? {
    if v != nil {
        return Optional.none
    }
    return Optional.some(nil)
}"""

renderUnion :: IRUnionRep -> Doc String
renderUnion ur =
    case nullableFromSet $ unionToSet ur of
    Just r -> do
        rendered <- renderType r
        pure $ rendered <> "?"
    Nothing -> lookupUnionName ur

renderType :: IRType -> Doc String
renderType = case _ of
    IRNothing -> pure "Any?"
    IRNull -> pure "Any?"
    IRInteger -> pure "Int"
    IRDouble -> pure "Double"
    IRBool -> pure "Bool"
    IRString -> pure "String"
    IRArray a -> do
        rendered <- renderType a
        pure $ "[" <> rendered <> "]"
    IRClass i -> lookupClassName i
    IRMap t -> do
        rendered <- renderType t
        pure $ "[String: " <> rendered <> "]"
    IRUnion ur -> renderUnion ur

renderClassDefinition :: String -> Map String IRType -> Doc Unit
renderClassDefinition className properties = do
    let forbidden = keywords <> ["jsonUntyped", "json"]
    let propertyNames = makePropertyNames "" forbidden
    line $ "struct " <> className <> " {"
    indent do
        forEachProperty_ properties propertyNames \_ ptype fieldName _ -> do
            rendered <- renderType ptype
            line $ "let " <> fieldName <> ": " <> rendered
        blank
        line $ "init?(_ jsonUntyped: Any) {"
        indent do
            line "guard let json = jsonUntyped as? [String: Any] else { return nil }"
            let forbiddenForUntyped = forbidden <> (A.fromFoldable $ M.keys propertyNames)
            let untypedNames = makePropertyNames "Untyped" forbiddenForUntyped
            let forbiddenForConverted = forbiddenForUntyped <> (A.fromFoldable $ M.keys untypedNames)
            let convertedNames = makePropertyNames "Converted" forbiddenForConverted
            forEachProperty_ properties untypedNames \pname ptype untypedName _ -> do
                when (canBeNull ptype) do
                    line $ "let " <> untypedName <> " = removeNSNull(json[\"" <> stringEscape pname <> "\"])"
            line "guard"
            indent do
                forEachProperty_ properties untypedNames \pname ptype untypedName isLast -> do
                    let convertedName = lookupName pname convertedNames
                    unless (canBeNull ptype) do
                        line $ "let " <> untypedName <> " = removeNSNull(json[\"" <> stringEscape pname <> "\"]),"
                    convertCode <- convert ptype untypedName
                    line $ "let " <> convertedName <> " = " <> convertCode <> (if isLast then "" else ",")
            line "else {"
            indent do
                line "return nil"
            line "}"
            forEachProperty_ properties propertyNames \pname _ fieldName _ -> do
                let convertedName = lookupName pname convertedNames
                line $ "self." <> fieldName <> " = " <> convertedName
        line "}"
    line "}"
    where
        isSimpleNullable :: IRType -> Boolean
        isSimpleNullable (IRUnion ur) = not $ unionIsNotSimpleNullable ur
        isSimpleNullable _ = false

        maybeCast :: IRType -> String
        maybeCast (IRArray _) = " as? [Any]"
        maybeCast (IRClass _) = " as? [String: Any]"
        maybeCast (IRMap _) = " as? [String: Any]"
        maybeCast _ = ""

        isBuiltInType :: IRType -> Boolean
        isBuiltInType (IRArray a) = isBuiltInType a
        isBuiltInType (IRMap m) = isBuiltInType m
        isBuiltInType (IRClass _) = false
        isBuiltInType (IRUnion ur) =
            case nullableFromSet $ unionToSet ur of
            Just t -> isBuiltInType t
            Nothing -> false
        isBuiltInType _ = true

        converterFunc :: IRType -> Doc String
        converterFunc (IRClass i) = do
            name <- lookupClassName i
            pure $ name <> ".init"
        converterFunc (IRUnion ur) = do
            name <- lookupUnionName ur
            pure $ name <> ".fromJson"
        converterFunc IRDouble =
            pure "convertDouble"
        converterFunc IRNull =
            pure "checkNull"
        converterFunc t = do
            converted <- convert t "$0"
            pure $ "{ " <> converted <> " }"

        convert :: IRType -> String -> Doc String
        convert (IRArray a) var = do
            converter <- converterFunc a
            pure $ "convertArray(converter: " <> converter <> ", json: " <> var <> ")"
        convert (IRMap m) var = do
            converter <- converterFunc m
            pure $ "convertDict(converter: " <> converter <> ", json: " <> var <> ")"
        convert (IRUnion ur) var =
            case nullableFromSet $ unionToSet ur of
            Just t -> do
                converter <- converterFunc t
                pure $ "convertOptional(converter: " <> converter <> ", json: " <> var <> ")"
            Nothing -> do
                name <- lookupUnionName ur
                pure $ name <> ".fromJson(" <> var <> ")"
        convert IRNothing var =
            pure $ "Optional.some(" <> var <> ")"
        convert IRBool var =
            pure $ var <> " as? Bool"
        convert IRInteger var =
            pure $ var <> " as? Int"
        convert IRString var =
            pure $ var <> " as? String"
        convert t var = do
            converter <- converterFunc t
            pure $ converter <> "(" <> var <> ")"

        forEachProperty_ :: Map String IRType -> Map String String -> (String -> IRType -> String -> Boolean -> Doc Unit) -> Doc Unit
        forEachProperty_ properties propertyNames f =
            let propertyArray = M.toUnfoldable properties :: Array _
                lastIndex = (A.length propertyArray) - 1
            in
                forWithIndex_ propertyArray \i (Tuple pname ptype) -> do
                    let fieldName = lookupName pname propertyNames
                    f pname ptype fieldName (i == lastIndex)

        makePropertyNames :: String -> Array String -> Map String String
        makePropertyNames suffix forbidden =
            transformPropertyNames (fieldNamer suffix) otherField forbidden properties

        fieldNamer :: String -> Namer String
        fieldNamer suffix =
            simpleNamer \name -> swiftNameStyle false name <> suffix

        otherField :: String -> String
        otherField name =
            "other" <> capitalize name

renderUnionDefinition :: String -> Set IRType -> Doc Unit
renderUnionDefinition unionName unionTypes = do
    let { element: emptyOrNull, rest: nonNullTypes } = removeElement (_ == IRNull) unionTypes
    line $ "enum " <> unionName <> " {"
    indent do
        for_ nonNullTypes \typ -> do
            name <- caseName typ
            rendered <- renderType typ
            line $ "case " <> name <> "(" <> rendered <> ")"
        case emptyOrNull of
            Just t -> do
                name <- caseName t
                line $ "case " <> name                
            Nothing -> pure unit
    line "}"
    where
        caseName :: IRType -> Doc String
        caseName = case _ of
            IRArray a -> do
                rendered <- renderType a
                pure $ "some" <> rendered <> "s"
            IRNull -> pure "none"
            t -> do
                rendered <- renderType t
                pure $ "some" <> rendered
