{-# LANGUAGE LambdaCase, OverloadedStrings, ViewPatterns #-}

module Mud.Data.State.Util.Coins ( aCoinSomeCoins
                                 , coinsFromList
                                 , coinsToList
                                 , distillEcs
                                 , mkCoinPieceTxt
                                 , mkCoinTxt
                                 , negateCoins ) where

import           Mud.Data.State.MudData
import           Mud.TopLvlDefs.Misc
import           Mud.Util.Misc (PatternMatchFail)
import qualified Mud.Util.Misc as U (pmf)
import           Mud.Util.Operators
import           Mud.Util.Text

import           Control.Lens (_1, _2, each)
import           Control.Lens.Operators ((&), (%~), (^..), (<>~))
import           Data.List (foldl')
import           Data.Monoid ((<>))
import           Data.Text (Text)
import qualified Data.Text as T

pmf :: PatternMatchFail
pmf = U.pmf "Mud.Data.State.Util.Coins"

-- ============================================================

aCoinSomeCoins :: Coins -> Text
aCoinSomeCoins = \case (Coins (1, 0, 0)) -> "a copper piece"
                       (Coins (0, 1, 0)) -> "a silver piece"
                       (Coins (0, 0, 1)) -> "a gold piece"
                       _                 -> "some coins"

coinsFromList :: [Int] -> Coins
coinsFromList [ cop, sil, gol ] = Coins (cop, sil, gol)
coinsFromList xs                = pmf "coinsFromList" xs

coinsToList :: Coins -> [Int]
coinsToList (Coins c) = c^..each

distillEcs :: [Either [Text] Coins] -> (Coins, [Text])
distillEcs = foldl' helper mempty
  where
    helper acc (Right c   ) = acc & _1 <>~ c
    helper acc (Left  msgs) = acc & _2 <>~ msgs

mkCoinTxt :: Coins -> Text
mkCoinTxt coins = case mkCoinTxtList of
  [ c, s, g ] -> T.concat [ c, ", ", s, ", and ", g ]
  [ x, y    ] -> x <> " and " <> y
  [ x       ] -> x
  [         ] -> ""
  xs          -> pmf "mkCoinTxt" xs
  where
    mkCoinTxtList = dropBlanks . foldr combineAmntName [] . zip (coinsToList coins) $ coinFullNames
    combineAmntName (amt, coinName) acc | amt >  1  = T.concat [ showTxt amt, " ", coinName, "s" ] : acc
                                        | amt == 1  = showTxt amt |<>| coinName : acc
                                        | otherwise = acc

mkCoinPieceTxt :: Coins -> (Text, Bool)
mkCoinPieceTxt = \case (Coins (1, 0, 0)) -> ("copper piece", False)
                       (Coins (0, 1, 0)) -> ("silver piece", False)
                       (Coins (0, 0, 1)) -> ("gold piece",   False)
                       _                 -> ("coins",        True )

negateCoins :: Coins -> Coins
negateCoins (Coins (each %~ negate -> c)) = Coins c
