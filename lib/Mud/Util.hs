{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE LambdaCase, OverloadedStrings, RankNTypes, ViewPatterns #-}

module Mud.Util ( aOrAn
                , adjustIndent
                , appendIfUnique
                , blowUp
                , bracketPad
                , bracketQuote
                , calcIndent
                , capitalize
                , countOcc
                , dblQuote
                , dblQuoteStr
                , deleteFirstOfEach
                , dropBlanks
                , eitherRet
                , findFullNameForAbbrev
                , grepTextList
                , headTail
                , headTail'
                , isVowel
                , maybeRet
                , maybeVoid
                , mkCountList
                , mkOrdinal
                , multiWrap
                , nl
                , nl'
                , nlnl
                , notInfixOf
                , padOrTrunc
                , parensPad
                , parensQuote
                , patternMatchFail
                , quoteWith
                , quoteWith'
                , quoteWithAndPad
                , reverseLookup
                , showText
                , singleQuote
                , stripControl
                , stripTelnet
                , uncapitalize
                , unquote
                , wordWrap
                , wordWrapIndent
                , wordWrapLines
                , wrapLineWithIndentTag
                , wrapUnlines
                , wrapUnlinesNl
                , xformLeading ) where

import Mud.TopLvlDefs

import Control.Applicative ((<$>), (<*>))
import Control.Lens (both, folded, over, to)
import Control.Lens.Operators ((^..))
import Control.Monad (guard)
import Data.Char (isDigit, isSpace, toLower, toUpper)
import Data.List (delete, foldl', sort)
import Data.Monoid ((<>))
import qualified Data.Map.Lazy as M (Map, assocs)
import qualified Data.Text as T


-- ==================================================
-- Error handling:


blowUp :: T.Text -> T.Text -> T.Text -> [T.Text] -> a
blowUp modName funName msg (bracketQuote . T.intercalate ", " . map singleQuote -> vals) =
    error . T.unpack . T.concat $ [ modName, " ", funName, ": ", msg, ". ", vals ]


patternMatchFail :: T.Text -> T.Text -> [T.Text] -> a
patternMatchFail modName funName = blowUp modName funName "pattern match failure"


-- ==================================================
-- Word wrapping and indenting:


wordWrap :: Int -> T.Text -> [T.Text]
wordWrap cols t
  | T.null afterMax                                 = [t]
  | T.any isSpace beforeMax
  , (beforeSpace, afterSpace) <- breakEnd beforeMax = beforeSpace : wordWrap cols (afterSpace <> afterMax)
  | otherwise                                       = beforeMax   : wordWrap cols afterMax
  where
    (beforeMax, afterMax) = T.splitAt cols t


breakEnd :: T.Text -> (T.Text, T.Text)
breakEnd (T.break isSpace . T.reverse -> (after, before)) = over both T.reverse (before, after)


wrapUnlines :: Int -> T.Text -> T.Text
wrapUnlines cols = T.unlines . wordWrap cols


wrapUnlinesNl :: Int -> T.Text -> T.Text
wrapUnlinesNl cols = nl . wrapUnlines cols


multiWrap :: Int -> [T.Text] -> T.Text
multiWrap cols = T.unlines . concatMap (wordWrap cols)


wordWrapIndent :: Int -> Int -> T.Text -> [T.Text]
wordWrapIndent n cols = map leadingFillerToSpcs . wrapIt . leadingSpcsToFiller
  where
    wrapIt t
      | T.null afterMax = [t]
      | T.any isSpace beforeMax, (beforeSpace, afterSpace) <- breakEnd beforeMax =
                    beforeSpace : wordWrapIndent n cols (leadingIndent <> afterSpace <> afterMax)
      | otherwise = beforeMax   : wordWrapIndent n cols (leadingIndent <> afterMax)
      where
        (beforeMax, afterMax) = T.splitAt cols t
        leadingIndent         = T.replicate (adjustIndent n cols) . T.singleton $ indentFiller


leadingSpcsToFiller :: T.Text -> T.Text
leadingSpcsToFiller = xformLeading ' ' indentFiller


leadingFillerToSpcs :: T.Text -> T.Text
leadingFillerToSpcs = xformLeading indentFiller ' '


xformLeading :: Char -> Char -> T.Text -> T.Text
xformLeading _ _                    ""                                        = ""
xformLeading a (T.singleton -> b) (T.break (/= a) -> (T.length -> n, rest)) = T.replicate n b <> rest


adjustIndent :: Int -> Int -> Int
adjustIndent n cols = if n >= cols then pred cols else n


wordWrapLines :: Int -> [T.Text] -> [[T.Text]]
wordWrapLines _    []                     = []
wordWrapLines cols [t]                    = [ wordWrapIndent (numOfLeadingSpcs t) cols t ]
wordWrapLines cols (a:b:rest) | T.null a  = [""]     : wrapNext
                              | otherwise = helper a : wrapNext
  where
    wrapNext         = wordWrapLines cols $ b : rest
    helper
      | hasIndentTag = wrapLineWithIndentTag cols
      | nolsa > 0    = wordWrapIndent nolsa  cols
      | nolsb > 0    = wordWrapIndent nolsb  cols
      | otherwise    = wordWrap cols
    hasIndentTag     = T.last a == indentTagChar
    (nolsa, nolsb)   = over both numOfLeadingSpcs (a, b)


numOfLeadingSpcs :: T.Text -> Int
numOfLeadingSpcs = T.length . T.takeWhile isSpace


wrapLineWithIndentTag :: Int -> T.Text -> [T.Text]
wrapLineWithIndentTag cols (T.break (not . isDigit) . T.reverse . T.init -> broken) = wordWrapIndent n cols t
  where
    (numTxt, t) = over both T.reverse broken
    readsRes    = reads . T.unpack $ numTxt :: [(Int, String)]
    extractInt []               = 0
    extractInt [(x, _)] | x > 0 = x
    extractInt xs               = patternMatchFail "Mud.Util" "wrapLineWithIndentTag extractInt" [ showText xs ]
    indent          = extractInt readsRes
    n | indent == 0 = calcIndent t
      | otherwise   = adjustIndent indent cols


calcIndent :: T.Text -> Int
calcIndent (T.break isSpace -> (T.length -> lenOfFirstWord, rest))
  | T.null rest = 0
  | otherwise   = lenOfFirstWord + numOfLeadingSpcs rest


-- ==================================================
-- Quoting:


quoteWith :: T.Text -> T.Text -> T.Text
quoteWith q = quoteWith' (q, q)


quoteWith' :: (T.Text, T.Text) -> T.Text -> T.Text
quoteWith' (a, b) t = T.concat [ a, t, b ]


singleQuote :: T.Text -> T.Text
singleQuote = quoteWith "'"


dblQuote :: T.Text -> T.Text
dblQuote = quoteWith "\""


dblQuoteStr :: String -> String
dblQuoteStr = T.unpack . dblQuote . T.pack


bracketQuote :: T.Text -> T.Text
bracketQuote = quoteWith' ("[", "]")


parensQuote :: T.Text -> T.Text
parensQuote = quoteWith' ("(", ")")


unquote :: T.Text -> T.Text
unquote = T.init . T.tail


-- ==================================================
-- Padding:


quoteWithAndPad :: (T.Text, T.Text) -> Int -> T.Text -> T.Text
quoteWithAndPad q x t = quoteWith' q t' <> T.replicate (x - T.length t' - 2) " "
  where
    t' = T.take (pred $ x - l) t
    l  = sum $ [ fst q, snd q ]^..folded.to T.length


bracketPad :: Int -> T.Text -> T.Text
bracketPad = quoteWithAndPad ("[", "]")


parensPad :: Int -> T.Text -> T.Text
parensPad = quoteWithAndPad ("(", ")")


padOrTrunc :: Int -> T.Text -> T.Text
padOrTrunc x _                 | x < 0 = ""
padOrTrunc x t@(T.length -> l) | l < x = t <> T.replicate (x - l) " "
                               | l > x = T.take x t
padOrTrunc _ t = t


-- ==================================================
-- Misc.:


aOrAn :: T.Text -> T.Text
aOrAn (T.strip -> t) | T.null t             = ""
                     | isVowel . T.head $ t = "an " <> t
                     | otherwise            = "a "  <> t


appendIfUnique :: (Eq a) => [a] -> a -> [a]
xs `appendIfUnique` x | x `elem` xs = xs
                      | otherwise   = xs ++ [x]


capitalize :: T.Text -> T.Text
capitalize = capsHelper toUpper


uncapitalize :: T.Text -> T.Text
uncapitalize = capsHelper toLower


capsHelper :: (Char -> Char) -> T.Text -> T.Text
capsHelper f (headTail' -> (h, t)) = (T.singleton . f $ h)  <> t


countOcc :: (Eq a) => a -> [a] -> Int
countOcc needle = foldl' (\acc x -> if x == needle then succ acc else acc) 0


deleteFirstOfEach :: (Eq a) => [a] -> [a] -> [a]
deleteFirstOfEach delThese fromThis = foldl' (flip delete) fromThis delThese


dropBlanks :: [T.Text] -> [T.Text]
dropBlanks []      = []
dropBlanks ("":xs) =     dropBlanks xs
dropBlanks ( x:xs) = x : dropBlanks xs


eitherRet :: (Monad m) => (a -> m b) -> Either a b -> m b
eitherRet = flip either return


findFullNameForAbbrev :: T.Text -> [T.Text] -> Maybe T.Text
findFullNameForAbbrev needle hay = guard (not . null $ res) >> (Just . head $ res)
  where
    res = sort . filter (needle `T.isPrefixOf`) $ hay


grepTextList :: T.Text -> [T.Text] -> [T.Text]
grepTextList needle = filter (needle `T.isInfixOf`)


headTail :: [a] -> (a, [a])
headTail = (,) <$> head <*> tail


headTail' :: T.Text -> (Char, T.Text)
headTail' txt = (T.head txt, T.tail txt)


isVowel :: Char -> Bool
isVowel = (`elem` "aeiou")


maybeRet :: Monad m => m a -> Maybe a -> m a
maybeRet dflt = maybe dflt return


maybeVoid :: (Monad m) => (a -> m ()) -> Maybe a -> m ()
maybeVoid = maybe (return ())


mkCountList :: (Eq a) => [a] -> [Int]
mkCountList xs = map (`countOcc` xs) xs


mkOrdinal :: Int -> T.Text
mkOrdinal 11              = "11th"
mkOrdinal 12              = "12th"
mkOrdinal 13              = "13th"
mkOrdinal (showText -> n) = n <> case T.last n of '1' -> "st"
                                                  '2' -> "nd"
                                                  '3' -> "rd"
                                                  _   -> "th"


nl :: T.Text -> T.Text
nl = (<> "\n")


nlnl :: T.Text -> T.Text
nlnl = nl . nl


nl' :: T.Text -> T.Text
nl' = ("\n" <>)


notInfixOf :: T.Text -> T.Text -> Bool
notInfixOf needle haystack = not $  needle `T.isInfixOf` haystack


reverseLookup :: (Eq v) => v -> M.Map k v -> k
reverseLookup v = fst . head . filter ((== v) . snd) . M.assocs


showText :: (Show a) => a -> T.Text
showText = T.pack . show


stripControl :: T.Text -> T.Text
stripControl = T.filter (\c -> c > '\31' && c < '\127')


stripTelnet :: T.Text -> T.Text
stripTelnet t
  | T.singleton telnetIAC `T.isInfixOf` t, (left, right) <- T.span (/= telnetIAC) t = left <> helper right
  | otherwise = t
  where
    helper (T.uncons -> Just (_, T.uncons -> Just (x, T.uncons -> Just (_, rest))))
      | x == telnetSB = case T.span (/= telnetSE) rest of (_, "")              -> ""
                                                          (_, T.tail -> rest') -> stripTelnet rest'
      | otherwise     = stripTelnet rest
    helper _ = ""
