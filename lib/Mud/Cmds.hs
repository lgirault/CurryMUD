{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE LambdaCase, MultiWayIf, OverloadedStrings, ScopedTypeVariables #-}

module Mud.Cmds (gameWrapper) where

import Mud.Logging hiding (logAndDispIOEx, logExMsg, logIOEx, logIOExRethrow, logNotice)
import Mud.MiscDataTypes
import Mud.NameResolution
import Mud.StateDataTypes
import Mud.StateInIORefT
import Mud.StateHelpers
import Mud.TheWorld
import Mud.TopLvlDefs
import Mud.Util hiding (blowUp, patternMatchFail)
import qualified Mud.Logging as L (logAndDispIOEx, logExMsg, logIOEx, logIOExRethrow, logNotice)
import qualified Mud.Util as U (blowUp, patternMatchFail)

import Control.Arrow (first)
import Control.Concurrent (forkIO, myThreadId)
import Control.Exception (ArithException(..), fromException, IOException, SomeException)
import Control.Exception.Lifted (catch, finally, throwIO, try)
import Control.Lens (_1, at, both, folded, over, to)
import Control.Lens.Operators ((&), (.~), (?~), (^.), (^..))
import Control.Monad ((>=>), forever, forM_, guard, mplus, replicateM_, unless, void, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State (get)
import Data.Char (isSpace, toUpper)
import Data.Functor ((<$>))
import Data.List (delete, find, foldl', intercalate, intersperse, nub, nubBy, sort)
import Data.Maybe (fromJust, isNothing)
import Data.Monoid ((<>), mempty)
import Data.Text.Strict.Lens (packed, unpacked)
import Data.Time (getCurrentTime, getZonedTime)
import Data.Time.Format (formatTime)
import System.Console.Readline (readline)
import System.Directory (getDirectoryContents, getTemporaryDirectory, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode(ExitSuccess), exitFailure, exitSuccess)
import System.IO (hClose, hGetBuffering, openTempFile)
import System.IO.Error (isDoesNotExistError, isPermissionError)
import System.Locale (defaultTimeLocale)
import System.Process (readProcess)
import System.Random (newStdGen, randomR) -- TODO: Use mwc-random or tf-random. QC uses tf-random.
import qualified Data.Map.Lazy as M (filter, toList)
import qualified Data.Text as T

{-# ANN module ("HLint: ignore Use camelCase" :: String) #-}


-- TODO: Write functions at the lowest level of the transformer stack as possible, then lift them?


blowUp :: T.Text -> T.Text -> [T.Text] -> a
blowUp = U.blowUp "Mud.Cmds"


patternMatchFail :: T.Text -> [T.Text] -> a
patternMatchFail = U.patternMatchFail "Mud.Cmds"


logNotice :: String -> String -> MudStack ()
logNotice = L.logNotice "Mud.Cmds"


logIOEx :: String -> IOException -> MudStack ()
logIOEx = L.logIOEx "Mud.Cmds"


logAndDispIOEx :: String -> IOException -> MudStack ()
logAndDispIOEx = L.logAndDispIOEx "Mud.Cmds"


logIOExRethrow :: String -> IOException -> MudStack ()
logIOExRethrow = L.logIOExRethrow "Mud.Cmds"


logExMsg :: String -> String -> SomeException -> MudStack ()
logExMsg = L.logExMsg "Mud.Cmds"


-- ==================================================


cmdList :: [Cmd]
cmdList = -- ==================================================
          -- Wizard commands:
          [ Cmd { cmdName = prefixWizCmd "?", action = wizDispCmdList, cmdDesc = "Display this command list." }
          , Cmd { cmdName = prefixWizCmd "day", action = wizDay, cmdDesc = "Display the current day of week." }
          , Cmd { cmdName = prefixWizCmd "shutdown", action = wizShutdown, cmdDesc = "Shut down the game server." }
          , Cmd { cmdName = prefixWizCmd "time", action = wizTime, cmdDesc = "Display the current system time." }

          -- ==================================================
          -- Debug commands:
          , Cmd { cmdName = prefixDebugCmd "?", action = debugDispCmdList, cmdDesc = "Display this command list." }
          , Cmd { cmdName = prefixDebugCmd "buffer", action = debugBuffCheck, cmdDesc = "Confirm the default buffering mode." }
          , Cmd { cmdName = prefixDebugCmd "env", action = debugDispEnv, cmdDesc = "Display system environment variables." }
          , Cmd { cmdName = prefixDebugCmd "log", action = debugLog, cmdDesc = "Put the logging service under heavy load." }
          , Cmd { cmdName = prefixDebugCmd "throw", action = debugThrow, cmdDesc = "Throw an exception." }

          -- ==================================================
          -- Player commands:
          , Cmd { cmdName = "?", action = plaDispCmdList, cmdDesc = "Display this command list." }
          , Cmd { cmdName = "about", action = about, cmdDesc = "About this game." }
          , Cmd { cmdName = "d", action = go "d", cmdDesc = "Go down." }
          , Cmd { cmdName = "drop", action = dropAction, cmdDesc = "Drop items on the ground." }
          , Cmd { cmdName = "e", action = go "e", cmdDesc = "Go east." }
          , Cmd { cmdName = "equip", action = equip, cmdDesc = "Display readied equipment." }
          , Cmd { cmdName = "exits", action = exits True, cmdDesc = "Display obvious exits." }
          , Cmd { cmdName = "get", action = getAction, cmdDesc = "Pick items up off the ground." }
          , Cmd { cmdName = "help", action = help, cmdDesc = "Get help on topics or commands." }
          , Cmd { cmdName = "inv", action = inv, cmdDesc = "Inventory." }
          , Cmd { cmdName = "look", action = look, cmdDesc = "Look." }
          , Cmd { cmdName = "motd", action = motd, cmdDesc = "Display the message of the day." }
          , Cmd { cmdName = "n", action = go "n", cmdDesc = "Go north." }
          , Cmd { cmdName = "ne", action = go "ne", cmdDesc = "Go northeast." }
          , Cmd { cmdName = "nw", action = go "nw", cmdDesc = "Go northwest." }
          , Cmd { cmdName = "put", action = putAction, cmdDesc = "Put items in a container." }
          , Cmd { cmdName = "quit", action = quit, cmdDesc = "Quit." }
          , Cmd { cmdName = "ready", action = ready, cmdDesc = "Ready items." }
          , Cmd { cmdName = "remove", action = remove, cmdDesc = "Remove items from a container." }
          , Cmd { cmdName = "s", action = go "s", cmdDesc = "Go south." }
          , Cmd { cmdName = "se", action = go "se", cmdDesc = "Go southeast." }
          , Cmd { cmdName = "sw", action = go "sw", cmdDesc = "Go southwest." }
          , Cmd { cmdName = "u", action = go "u", cmdDesc = "Go up." }
          , Cmd { cmdName = "unready", action = unready, cmdDesc = "Unready items." }
          , Cmd { cmdName = "uptime", action = uptime, cmdDesc = "Display game server uptime." }
          , Cmd { cmdName = "w", action = go "w", cmdDesc = "Go west." }
          , Cmd { cmdName = "what", action = what, cmdDesc = "Disambiguate abbreviations." } ]


prefixCmd :: Char -> CmdName -> T.Text
prefixCmd c cn = [c]^.packed <> cn


prefixWizCmd :: CmdName -> T.Text
prefixWizCmd = prefixCmd wizCmdChar


prefixDebugCmd :: CmdName -> T.Text
prefixDebugCmd = prefixCmd debugCmdChar


gameWrapper :: MudStack ()
gameWrapper = (initAndStart `catch` topLvlExHandler) `finally` closeLogs
  where
    initAndStart = do
        initLogging
        logNotice "gameWrapper" "server started"
        sequence_ . intersperse (liftIO newLine) $ [initWorld, dispTitle, motd []]
        forever game


topLvlExHandler :: SomeException -> MudStack ()
topLvlExHandler e = let oops msg = logExMsg "topLvlExHandler" msg e >> liftIO exitFailure
                    in case fromException e of
                      Just ExitSuccess -> logNotice "topLvlExHandler" "exiting normally"
                      Just _           -> oops $ dblQuoteStr "ExitFailure" ++ " caught by the top level handler; rethrowing"
                      Nothing          -> oops "exception caught by the top level handler; exiting gracefully"


dispTitle :: MudStack ()
dispTitle = liftIO newStdGen >>= \g ->
    let range = (1, noOfTitles)
        n     = randomR range g^._1
        fn    = "title"^.unpacked ++ show n
    in (try . liftIO . takeADump $ fn) >>= eitherRet dispTitleExHandler
  where
    takeADump = dumpFileNoWrapping . (++) titleDir


dispTitleExHandler :: IOException -> MudStack ()
dispTitleExHandler e = f "dispTitle" e
  where
    f = if | isDoesNotExistError e -> logIOEx
           | isPermissionError   e -> logIOEx
           | otherwise             -> logIOExRethrow


game :: MudStack ()
game = do
    ms <- liftIO . readline $ "> "
    let t = ms^.to fromJust.packed.to T.strip
    unless (T.null t) $ handleInp t


handleInp :: T.Text -> MudStack ()
handleInp = maybeRet dispatch . splitInp


type Input = (CmdName, Rest)


splitInp :: T.Text -> Maybe Input
splitInp = splitUp . T.words
  where
    splitUp []     = Nothing
    splitUp [t]    = Just (t, [])
    splitUp (t:ts) = Just (t, ts)


dispatch :: Input -> MudStack ()
dispatch (cn, rest) = findAction cn >>= maybe (output $ "What?" <> nlt) (\act -> act rest)


findAction :: CmdName -> MudStack (Maybe Action)
findAction cn = do
    cmdList' <- getPCRmId 0 >>= mkCmdListWithRmLinks
    let cns = map cmdName cmdList'
    maybe (return Nothing)
          (\fn -> return . Just . findActionForFullName fn $ cmdList')
          (findFullNameForAbbrev (T.toLower cn) cns)
  where
    findActionForFullName fn = action . head . filter ((== fn) . cmdName)


mkCmdListWithRmLinks :: Id -> MudStack [Cmd]
mkCmdListWithRmLinks i = getRmLinks i >>= \rls ->
    return (cmdList ++ [ mkCmdForRmLink rl | rl <- rls, rl^.linkName `notElem` stdLinkNames ])
  where
    mkCmdForRmLink rl = let ln = rl^.linkName.to T.toLower
                        in Cmd { cmdName = ln, action = go ln, cmdDesc = "" }


-- ==================================================
-- Player commands:


about :: Action
about [] = try takeADump >>= eitherRet (dumpExHandler "about") >> liftIO newLine
  where
    takeADump = dumpFile . (++) miscDir $ "about"
about rs = ignore rs >> about []


dumpExHandler :: String -> IOException -> MudStack ()
dumpExHandler fn e = handleThat >> dispGenericErrorMsg
  where
    handleThat
      | isDoesNotExistError e = logIOEx fn e
      | isPermissionError   e = logIOEx fn e
      | otherwise             = logIOExRethrow fn e


ignore :: Rest -> MudStack ()
ignore rs = let ignored = dblQuote . T.unwords $ rs
            in output ("(Ignoring " <> ignored <> "...)")


-----


motd :: Action
motd [] = try takeADump >>= eitherRet (dumpExHandler "motd") >> liftIO newLine
  where
    takeADump = dumpFileWithDividers . (++) miscDir $ "motd"
motd rs = ignore rs >> motd []


-----


plaDispCmdList :: Action
plaDispCmdList = dispCmdList (cmdPred Nothing)


dispCmdList :: (Cmd -> Bool) -> Action
dispCmdList p [] = mapM_ (outputIndent 10) (cmdListText p) >> liftIO newLine
dispCmdList p rs = forM_ rs $ \r ->
    mapM_ (outputIndent 10) (grepTextList r . cmdListText $ p)  >> liftIO newLine


cmdListText :: (Cmd -> Bool) -> [T.Text]
cmdListText p = sort . T.lines . T.concat . foldl' mkTxtForCmd [] . filter p $ cmdList
  where
    mkTxtForCmd acc c = T.concat [ padOrTrunc 10 . cmdName $ c, cmdDesc c, "\n" ] : acc


cmdPred :: Maybe Char -> Cmd -> Bool
cmdPred (Just c) cmd = c == (T.head . cmdName $ cmd)
cmdPred Nothing  cmd = (T.head . cmdName $ cmd) `notElem` [wizCmdChar, debugCmdChar]


-----


help :: Action
help [] = try takeADump >>= eitherRet (dumpExHandler "help")
  where
    takeADump = dumpFile . (++) helpDir $ "root"
help rs = sequence_ . intercalate [divider >> liftIO newLine] $ [ [dispHelpTopicByName r] | r <- rs ]


type HelpTopic = T.Text


dispHelpTopicByName :: HelpTopic -> MudStack ()
dispHelpTopicByName r = (liftIO . getDirectoryContents $ helpDir) >>= \fns ->
    let fns' = tail . tail . sort . delete "root" $ fns
        tns  = fns'^..folded.packed
    in maybe sorry
             helper
             (findFullNameForAbbrev r tns)
  where
    sorry     = output "No help is available on that topic/command."
    helper tn = (try . takeADump $ tn) >>= eitherRet (dumpExHandler "dispHelpTopicByName") >> liftIO newLine
    takeADump = dumpFile . (++) helpDir . T.unpack


-----


what :: Action
what [] = advise ["what"] $ "Please specify an abbreviation to confirm, as in " <> dblQuote "what up" <> "."
what rs = mapM_ helper rs
  where
    helper r = whatCmd >> whatInv PCInv r >> whatInv PCEq r >> whatInv RmInv r >> liftIO newLine
      where
        whatCmd  = (findFullNameForAbbrev (T.toLower r) <$> cs) >>= maybe notFound found
        cs       = filter ((/=) wizCmdChar . T.head) <$> map cmdName <$> (getPCRmId 0 >>= mkCmdListWithRmLinks)
        notFound = output $ dblQuote r <> " doesn't refer to any commands."
        found cn = outputCon [ dblQuote r, " may refer to the ", dblQuote cn, " command." ]


advise :: [HelpTopic] -> T.Text -> MudStack ()
advise []  msg = output . (<>) msg $ nlt
advise [h] msg = output msg >> outputCon [ "For more information, type ", dblQuote . (<>) "help " $ h, ".", nlt ]
advise hs  msg = output msg >> outputCon [ "See also the following help topics: ", helpTopics,         ".", nlt ]
  where
    helpTopics = dblQuote . T.intercalate (dblQuote ", ") $ hs


whatInv :: InvType -> T.Text -> MudStack ()
whatInv it r = do
    ic@(is, _)      <- getLocInvCoins it
    (gecrs, _, rcs) <- resolveEntCoinNames [r] ic
    if not . null $ gecrs
      then whatInvEnts it r (head gecrs) is
      else mapM_ (whatInvCoins it r) rcs
  where
    getLocInvCoins = \case PCInv -> getInvCoins 0
                           PCEq  -> getEq 0 >>= \is -> return (is, mempty)
                           RmInv -> getPCRmInvCoins 0


whatInvEnts :: InvType -> T.Text -> GetEntsCoinsRes -> Inv -> MudStack ()
whatInvEnts it r gecr is = case gecr of
  Mult _ n (Just es) _ | n == acp  -> outputCon [ dblQuote acp, " may refer to everything ", getLocTxtForInvType it, supplement, "." ]
                       | otherwise -> let e   = head es
                                          len = length es
                                      in if len > 1
                                        then let ebgns  = take len [ getEntBothGramNos e' | e' <- es ]
                                                 h      = head ebgns
                                                 target = if all (== h) ebgns then mkPlurFromBoth h else e^.name.to bracketQuote <> "s"
                                             in outputCon [ dblQuote r, " may refer to the ", showText len, " ", target, " ", getLocTxtForInvType it, "." ]
                                        else getEntNamesInInv is >>= \ens ->
                                            outputCon [ dblQuote r, " may refer to the ", checkFirst e ens ^.packed, e^.sing, " ", getLocTxtForInvType it, "." ]
  Indexed x _ (Right e) -> outputCon [ dblQuote r, " may refer to the ", mkOrdinal x, " ", e^.name.to bracketQuote, " ", e^.sing.to parensQuote, " ", getLocTxtForInvType it, "." ]
  _                     -> outputCon [ dblQuote r, " doesn't refer to anything ", getLocTxtForInvType it, "." ]
  where
    acp                                   = [allChar]^.packed
    supplement | it `elem` [PCInv, RmInv] = " (including any coins)"
               | otherwise                = ""
    checkFirst e ens                      = let matches = filter (== e^.name) ens
                                            in guard (length matches > 1) >> ("first "^.unpacked)


getLocTxtForInvType :: InvType -> T.Text
getLocTxtForInvType = \case PCInv -> "in your inventory"
                            PCEq  -> "in your readied equipment"
                            RmInv -> "in this room"


whatInvCoins :: InvType -> T.Text -> ReconciledCoins -> MudStack ()
whatInvCoins it r rc
  | it == PCEq = return ()
  | otherwise = case rc of
    Left  Empty      -> outputCon [ dblQuote r, " doesn't refer to any coins ", getLocTxtForInvType it, " ", supplementNone "coins" it, "." ]
    Left  (NoneOf c) -> let cn = mkTxtForCoins c in outputCon [ dblQuote r, " doesn't refer to any ", cn, " ", getLocTxtForInvType it, " ", supplementNone cn it, "." ]
    Left  (SomeOf c) -> let cn = mkTxtForCoins c in outputCon [ dblQuote r, " doesn't refer to any ", cn, " ", getLocTxtForInvType it, " ", supplementNotEnough cn it, "." ]
    Right (SomeOf c) -> outputCon [ dblQuote r, " refers to ", mkTxtForCoinsWithAmt c, " ", getLocTxtForInvType it, "." ]
    _                -> patternMatchFail "whatInvCoins" [ showText rc ]
  where
    supplementNone cn      = \case PCInv -> "(you don't have any " <> cn <> ")"
                                   RmInv -> "(there aren't any "   <> cn <> " here)"
                                   PCEq  -> oops "supplementNone"
    supplementNotEnough cn = \case PCInv -> "(you don't have that many " <> cn <> ")"
                                   RmInv -> "(there aren't that many "   <> cn <> " here)"
                                   PCEq  -> oops "supplementNotEnough"
    oops fn                = blowUp ("whatInvCoins " <> fn) "called for InvType of PCEq" []
    mkTxtForCoins c@(Coins (cop, sil, gol))
      | cop /= 0  = "copper pieces"
      | sil /= 0  = "silver pieces"
      | gol /= 0  = "gold pieces"
      | otherwise = blowUp "whatInvCoins mkTxtForCoins" "attempted to make text for empty coins" [ showText c ]
    mkTxtForCoinsWithAmt c@(Coins (cop, sil, gol))
      | cop == 1  = "1 copper piece"
      | cop /= 0  = showText cop <> " copper pieces"
      | sil == 1  = "1 silver piece"
      | sil /= 0  = showText sil <> " silver pieces"
      | gol == 1  = "1 gold piece"
      | gol /= 0  = showText gol <> " gold pieces"
      | otherwise = blowUp "whatInvCoins mkTxtForCoinsWithAmt" "attempted to make text for empty coins" [ showText c ]


-----


go :: T.Text -> Action
go dir [] = goDispatcher [dir]
go dir rs = goDispatcher $ dir : rs


goDispatcher :: Action
goDispatcher []     = return ()
goDispatcher rs     = mapM_ tryMove rs


tryMove :: T.Text -> MudStack ()
tryMove dir = let dir' = T.toLower dir
              in getPCRmId 0 >>= findExit dir' >>= maybe (sorry dir') (movePC 0)
  where
    sorry dir' = output $ if dir' `elem` stdLinkNames
                            then "You can't go that way." <> nlt
                            else dblQuote dir <> " is not a valid direction." <> nlt
    movePC pci ri = getPC pci >>= \p -> updateWS pci pcTbl (p & rmId .~ ri) >> look []


-----


look :: Action
look [] = do
    descRm
    summarizeExits
    getPCRmInvCoins 0 >>= dispRmInvCoins
    liftIO newLine
  where
    descRm = getPCRm 0 >>= \r -> output $ r^.name <> nlt <> r^.desc
    summarizeExits = exits False []
look rs = do
    hic <- getPCRmId 0 >>= hasInvOrCoins
    if hic
      then do
          (gecrs, miss, rcs) <- getPCRmInvCoins 0 >>= resolveEntCoinNames rs
          mapM_ (procGecrMisRm True descEnts) . zip gecrs $ miss
          mapM_ (procReconciledCoinsRm True descCoins) rcs
      else output $ "You don't see anything here to look at." <> nlt


dispRmInvCoins :: InvCoins -> MudStack ()
dispRmInvCoins (is, c) = mkNameCountBothList is >>= mapM_ dispEntInRm >> maybeSummarizeCoins
  where
    dispEntInRm (en, count, (s, _))
      | count == 1             = outputIndent 2 $ aOrAn s <> " " <> bracketQuote en
    dispEntInRm (en, count, b) = outputConIndent 2 [ showText count, " ", mkPlurFromBoth b, " ", bracketQuote en ]
    maybeSummarizeCoins        = when (c /= mempty) (summarizeCoins c)


mkNameCountBothList :: Inv -> MudStack [(T.Text, Int, BothGramNos)]
mkNameCountBothList is = do
    ens <- getEntNamesInInv is
    ebgns <- getEntBothGramNosInInv is
    let cs = mkCountList ebgns
    return (nub . zip3 ens cs $ ebgns)


descEnts :: Inv -> MudStack ()
descEnts is = forM_ is $ \i ->
    getEnt i >>= descEnt >> liftIO newLine


descEnt :: Ent -> MudStack ()
descEnt e = do
    e^.desc.to output
    t <- getEntType e
    when (t == ConType) $ dispInvCoins i
    when (t == MobType) $ dispEq i
  where
    i = e^.entId


dispInvCoins :: Id -> MudStack ()
dispInvCoins i = do
    hi <- hasInv   i
    hc <- hasCoins i
    case (hi, hc) of
      (False, False) -> if i == 0
                         then dudeYourHandsAreEmpty
                         else getEnt i >>= \e -> output $ "The " <> e^.sing <> " is empty."
      (True,  False) -> header >> dispEntsInInv i
      (False, True ) -> header >> summarizeCoinsInInv
      (True,  True ) -> header >> dispEntsInInv i >> summarizeCoinsInInv
  where
    header
      | i == 0 = output "You are carrying:"
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " contains:"
    summarizeCoinsInInv = getCoins i >>= summarizeCoins


dudeYourHandsAreEmpty :: MudStack ()
dudeYourHandsAreEmpty = output "You aren't carrying anything."


dispEntsInInv :: Id -> MudStack ()
dispEntsInInv i = getInv i >>= mkNameCountBothList >>= mapM_ dispEntInInv
  where
    dispEntInInv (en, c, (s, _))
      | c == 1 = outputIndent ind $ nameCol en <> "1 " <> s
    dispEntInInv (en, c, b) = outputConIndent ind [ nameCol en, showText c, " ", mkPlurFromBoth b ]
    nameCol = bracketPad ind
    ind     = 11


summarizeCoins :: Coins -> MudStack ()
summarizeCoins c = dispCoinsWithNamesList mkCoinsWithNamesList
  where
    dispCoinsWithNamesList = output . T.intercalate ", " . filter (not . T.null) . map dispNameAmt
    dispNameAmt (cn, a)    = if a == 0 then "" else showText a <> " " <> bracketQuote cn
    mkCoinsWithNamesList   = zip coinNames . mkCoinsList $ c


descCoins :: Coins -> MudStack ()
descCoins (Coins (cop, sil, gol)) = descCop >> descSil >> descGol
  where -- TODO: Come up with good descriptions.
    descCop = unless (cop == 0) $ output ("The copper piece is round and shiny." <> nlt)
    descSil = unless (sil == 0) $ output ("The silver piece is round and shiny." <> nlt)
    descGol = unless (gol == 0) $ output ("The gold piece is round and shiny."   <> nlt)


-----


exits :: ShouldNewLine -> Action
exits snl [] = do
    rlns <- map (^.linkName) <$> (getPCRmId 0 >>= getRmLinks)
    let stdNames    = [ sln | sln <- stdLinkNames, sln `elem` rlns ]
    let customNames = filter (`notElem` stdLinkNames) rlns
    output . (<>) "Obvious exits: " . T.intercalate ", " . (++) stdNames $ customNames
    maybeNewLine snl
exits nl rs = ignore rs >> exits nl []


-----


inv :: Action -- TODO: Give some indication of encumbrance.
inv [] = dispInvCoins 0 >> liftIO newLine
inv rs = do
    hic <- hasInvOrCoins 0
    if hic
      then do
          (gecrs, miss, rcs) <- getInvCoins 0 >>= resolveEntCoinNames rs
          mapM_ (procGecrMisPCInv True descEnts) . zip gecrs $ miss
          mapM_ (procReconciledCoinsPCInv True descCoins) rcs
      else dudeYourHandsAreEmpty >> liftIO newLine


-----


equip :: Action
equip [] = dispEq 0
equip rs = do
    he <- hasEq 0
    if he
      then do
          (gecrs, miss, rcs) <- getEq 0 >>= \is -> resolveEntCoinNames rs (is, mempty)
          mapM_ (procGecrMisPCInv True descEnts) . zip gecrs $ miss
          unless (null rcs) $ output ("You don't have any coins among your readied equipment." <> nlt)
      else dudeYou'reNaked


dispEq :: Id -> MudStack ()
dispEq i = (mkEqList . mkSlotNameToIdList . M.toList =<< getEqMap i) >>= \edl ->
    if null edl then none else header >> forM_ edl (outputIndent 15) >> liftIO newLine
  where
    mkSlotNameToIdList    = map (first pp)
    mkEqList              = mapM dispEqHelper
    dispEqHelper (sn, i') = let slotName = parensPad 15 noFinger
                                noFinger = T.breakOn " finger" sn ^._1
                            in getEnt i' >>= \e ->
                                return (T.concat [ slotName, e^.sing, " ", e^.name.to bracketQuote ])
    none
      | i == 0    = dudeYou'reNaked
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " doesn't have anything readied."
    header
      | i == 0    = output "You have readied the following equipment:"
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " has readied the following equipment:"


dudeYou'reNaked :: MudStack ()
dudeYou'reNaked = output $ "You don't have anything readied. You're naked!" <> nlt


-----


getAction :: Action
getAction [] = advise ["get"] $ "Please specify one or more items to pick up, as in " <> dblQuote "get sword" <> "."
getAction rs = do
    hic <- getPCRmId 0 >>= hasInvOrCoins
    if hic
      then do
        (gecrs, miss, rcs) <- getPCRmInvCoins 0 >>= resolveEntCoinNames rs
        mapM_ (procGecrMisRm False shuffleInvGet) . zip gecrs $ miss
        mapM_ (procReconciledCoinsRm False shuffleCoinsGet) rcs
        liftIO newLine
      else output $ "You don't see anything here to pick up." <> nlt


shuffleInvGet :: Inv -> MudStack ()
shuffleInvGet is = getPCRmId 0 >>= \i ->
    moveInv is i 0 >> descGetDropEnts Get is


descGetDropEnts :: GetOrDrop -> Inv -> MudStack ()
descGetDropEnts god is = mkNameCountBothList is >>= mapM_ descGetDropHelper
  where
    descGetDropHelper (_, c, (s, _))
      | c == 1                   = outputCon [ "You ", verb god, " the ", s, "." ]
    descGetDropHelper (_, c, b) = outputCon [ "You ", verb god, " ", showText c, " ", mkPlurFromBoth b, "." ]
    verb = \case Get  -> "pick up"
                 Drop -> "drop"


shuffleCoinsGet :: Coins -> MudStack ()
shuffleCoinsGet c = getPCRmId 0 >>= \i ->
    moveCoins c i 0 >> descGetDropCoins Get c


descGetDropCoins :: GetOrDrop -> Coins -> MudStack ()
descGetDropCoins god (Coins (cop, sil, gol)) = do
    unless (cop == 0) . descGetDropHelper cop $ "copper piece"
    unless (sil == 0) . descGetDropHelper sil $ "silver piece"
    unless (gol == 0) . descGetDropHelper gol $ "gold piece"
  where
    descGetDropHelper a cn
      | a == 1     = outputCon [ "You ", verb god, " a ", cn, "." ]
      | otherwise = outputCon [ "You ", verb god, " ", showText a, " ", cn, "s." ]
    verb = \case Get  -> "pick up"
                 Drop -> "drop"


-----


dropAction :: Action
dropAction [] = advise ["drop"] $ "Please specify one or more items to drop, as in " <> dblQuote "drop sword" <> "."
dropAction rs = do
    hic <- hasInvOrCoins 0
    if hic
      then do
          (gecrs, miss, rcs) <- getInvCoins 0 >>= resolveEntCoinNames rs
          mapM_ (procGecrMisPCInv False shuffleInvDrop) . zip gecrs $ miss
          mapM_ (procReconciledCoinsPCInv False shuffleCoinsDrop) rcs
      else dudeYourHandsAreEmpty
    liftIO newLine


shuffleInvDrop :: Inv -> MudStack ()
shuffleInvDrop is = getPCRmId 0 >>= \i ->
    moveInv is 0 i >> descGetDropEnts Drop is


shuffleCoinsDrop :: Coins -> MudStack ()
shuffleCoinsDrop c = getPCRmId 0 >>= \i ->
    moveCoins c 0 i >> descGetDropCoins Drop c


-----


putAction :: Action
putAction []   = advise ["put"] $ "Please specify what you want to put, followed by where you want to put it, as in " <> dblQuote "put doll sack" <> "."
putAction [r]  = advise ["put"] $ "Please also specify where you want to put it, as in " <> dblQuote ("put " <> r <> " sack") <> "."
putAction rs   = do
    hic <- hasInvOrCoins 0
    if hic
      then putRemDispatcher Put rs
      else dudeYourHandsAreEmpty
    liftIO newLine


putRemDispatcher :: PutOrRem -> Action
putRemDispatcher por rs
  | T.head cn == rmChar = getPCRmId 0 >>= hasInv >>= \hi ->
      if hi
        then putRemDispatcherHelper por (T.tail cn) (getPCRmInvCoins 0) procGecrMisRmForInv restWithoutCon
        else output "You don't see any containers here."
  | otherwise = putRemDispatcherHelper por cn (getInvCoins 0) procGecrMisPCInvForInv restWithoutCon
  where
    cn             = last rs
    restWithoutCon = init rs


putRemDispatcherHelper :: PutOrRem -> ConName -> MudStack InvCoins -> ((GetEntsCoinsRes, Maybe Inv) -> MudStack Inv) -> Action
putRemDispatcherHelper por cn f g rs = f >>= resolveEntCoinNames [cn] >>= \(gecrs, miss, rcs) ->
    if null miss && (not . null $ rcs)
      then sorryCoins por
      else (g . head . zip gecrs $ miss) >>= \case
        []  -> return ()
        [i] -> do
            e <- getEnt i
            t <- getEntType e
            if t /= ConType
              then output $ "The " <> e^.sing <> " isn't a container."
              else dispatchPutRem i por
        _   -> sorryOnlyOne por
  where
    sorryCoins       = \case Put -> output "You can't put something inside a coin."
                             Rem -> output "You can't remove something from a coin."
    sorryOnlyOne     = \case Put -> output "You can only put things into one container at a time."
                             Rem -> output "You can only remove things from one container at a time."
    dispatchPutRem i = \case Put -> putHelper i rs
                             Rem -> remHelper i rs


putHelper :: Id -> Rest -> MudStack ()
putHelper _  [] = return ()
putHelper ci rs = do
    (gecrs, miss, rcs) <- getInvCoins 0 >>= resolveEntCoinNames rs
    mapM_ (procGecrMisPCInv False . shuffleInvPut $ ci) . zip gecrs $ miss
    mapM_ (procReconciledCoinsPCInv False . shuffleCoinsPut $ ci) rcs


shuffleInvPut :: Id -> Inv -> MudStack ()
shuffleInvPut ci is = do
    cn  <- (^.sing) <$> getEnt ci
    is' <- checkImplosion cn
    moveInv is' 0 ci
    descPutRemEnts Put is' cn
  where
    checkImplosion cn = if ci `elem` is
                          then output ("You can't put the " <> cn <> " inside itself.") >> return (filter (/= ci) is)
                          else return is


descPutRemEnts :: PutOrRem -> Inv -> ConName -> MudStack ()
descPutRemEnts por is cn = mkNameCountBothList is >>= mapM_ descPutRemHelper
  where
    descPutRemHelper (_, c, (s, _))
      | c == 1                  = outputCon [ "You ", verb por, " the ", s, " ", prep por, " ", cn, "." ]
    descPutRemHelper (_, c, b) = outputCon [ "You ", verb por, " ", showText c, " ", mkPlurFromBoth b, " ", prep por, " ", cn, "." ]
    verb = \case Put -> "put"
                 Rem -> "remove"
    prep = \case Put -> "in the"
                 Rem -> "from the"


shuffleCoinsPut :: Id -> Coins -> MudStack ()
shuffleCoinsPut ci c = moveCoins c 0 ci >> (^.sing) <$> getEnt ci >>= descPutRemCoins Put c


descPutRemCoins :: PutOrRem -> Coins -> ConName -> MudStack ()
descPutRemCoins por (Coins (cop, sil, gol)) cn = do
    unless (cop == 0) . descPutRemHelper cop $ "copper piece"
    unless (sil == 0) . descPutRemHelper sil $ "silver piece"
    unless (gol == 0) . descPutRemHelper gol $ "gold piece"
  where
    descPutRemHelper a cn'
      | a == 1     = outputCon [ "You ", verb por, " a ", cn', " ", prep por, " ", cn, "." ]
      | otherwise = outputCon [ "You ", verb por, " ", showText a, " ", cn', "s ", prep por, " ", cn, "." ]
    verb = \case Put -> "put"
                 Rem -> "remove"
    prep = \case Put -> "in the"
                 Rem -> "from the"


-----


remove :: Action
remove []  = advise ["remove"] $ "Please specify what you want to remove, followed by the container you want to remove it from, as in " <> dblQuote "remove doll sack" <> "."
remove [r] = advise ["remove"] $ "Please also specify the container you want to remove it from, as in " <> dblQuote ("remove " <> r <> " sack") <> "."
remove rs  = putRemDispatcher Rem rs >> liftIO newLine


remHelper :: Id -> Rest -> MudStack ()
remHelper _  [] = return ()
remHelper ci rs = do
    cn  <- (^.sing) <$> getEnt ci
    hic <- hasInvOrCoins ci
    if not hic
      then output $ "The " <> cn <> " appears to be empty."
      else do
          (gecrs, miss, rcs) <- getInvCoins ci >>= resolveEntCoinNames rs
          mapM_ (procGecrMisCon cn . shuffleInvRem ci $ cn) . zip gecrs $ miss
          mapM_ (procReconciledCoinsCon cn . shuffleCoinsRem $ ci) rcs


shuffleInvRem :: Id -> ConName -> Inv -> MudStack ()
shuffleInvRem ci cn is = moveInv is ci 0 >> descPutRemEnts Rem is cn


shuffleCoinsRem :: Id -> Coins -> MudStack ()
shuffleCoinsRem ci c = moveCoins c ci 0 >> (^.sing) <$> getEnt ci >>= descPutRemCoins Rem c


-----


-- TODO: "ready" and "unready" and talking smack about coins.
-- > re sw
-- You wield the short sword with your right hand.
-- You can't ready coins.


ready :: Action
ready []   = advise ["ready"] $ "Please specify one or more things to ready, as in " <> dblQuote "ready sword" <> "."
ready (rs) = hasInv 0 >>= \hi -> if not hi then dudeYourHandsAreEmpty else do
    (gecrs, mrols, mis, rcs) <- getInvCoins 0 >>= resolveEntCoinNamesWithRols rs
    mapM_ (procGecrMrolMiss readyDispatcher) $ zip3 gecrs mrols mis
    unless (null rcs) $ output "You can't ready coins."
    liftIO newLine


readyDispatcher :: Maybe RightOrLeft -> Inv -> MudStack ()
readyDispatcher mrol = mapM_ dispatchByType
  where
    dispatchByType i = do
        e <- getEnt i
        em <- getEqMap 0
        getEntType e >>= \case
          ClothType -> getCloth i >>= \c -> readyCloth i e c em mrol
          WpnType   -> readyWpn i e em mrol
          _         -> output $ "You can't ready a " <> e^.sing <> "."


-- Helpers for the entity type-specific ready functions:


moveReadiedItem :: Id -> EqMap -> Slot -> MudStack ()
moveReadiedItem i em s = updateWS 0 eqTbl (em & at s ?~ i) >> remFromInv [i] 0


otherGender :: Gender -> Gender
otherGender Male     = Female
otherGender Female   = Male
otherGender NoGender = NoGender


otherHand :: Hand -> Hand
otherHand RHand  = LHand
otherHand LHand  = RHand
otherHand NoHand = NoHand


isRingRol :: RightOrLeft -> Bool
isRingRol = \case R -> False
                  L -> False
                  _ -> True


rEarSlots, lEarSlots, noseSlots, neckSlots, rWristSlots, lWristSlots :: [Slot]
rEarSlots   = [REar1S, REar2S]
lEarSlots   = [LEar1S, LEar2S]
noseSlots   = [Nose1S, Nose2S]
neckSlots   = [Neck1S   .. Neck3S]
rWristSlots = [RWrist1S .. RWrist3S]
lWristSlots = [LWrist1S .. LWrist3S]


isSlotAvail :: EqMap -> Slot -> Bool
isSlotAvail em s = isNothing $ em^.at s


findAvailSlot :: EqMap -> [Slot] -> Maybe Slot
findAvailSlot em = find (isSlotAvail em)


sorryFullClothSlots :: Cloth -> MudStack ()
sorryFullClothSlots = output . (<>) "You can't wear any more " . whatWhere
  where
    whatWhere = \case
      EarC      -> aoy <> "ears."
      NoseC     -> "rings on your nose."
      NeckC     -> aoy <> "neck."
      WristC    -> aoy <> "wrists."
      FingerC   -> aoy <> "fingers."
      UpBodyC   -> coy <> "torso."
      LowBodyC  -> coy <> "legs."
      FullBodyC -> "clothing about your body."
      BackC     -> "on your back."
      FeetC     -> "footwear on your feet."
    aoy = "accessories on your "
    coy = "clothing on your "


sorryFullClothSlotsOneSide :: Slot -> MudStack ()
sorryFullClothSlotsOneSide s = output $ "You can't wear any more on your " <> pp s <> "."


-- Ready clothing:


readyCloth :: Int -> Ent -> Cloth -> EqMap -> Maybe RightOrLeft -> MudStack ()
readyCloth i e c em mrol = maybe (getAvailClothSlot c em) (getDesigClothSlot e c em) mrol >>= \ms ->
    maybeRet (\s -> moveReadiedItem i em s >> readiedMsg s c) ms
  where
    readiedMsg s = \case NoseC   -> putOnMsg
                         NeckC   -> putOnMsg
                         FingerC -> outputCon [ "You slide the ", e^.sing, " on your ", pp s, "." ]
                         _       -> wearMsg
      where
        putOnMsg = output $ "You put on the " <> e^.sing <> "."
        wearMsg  = outputCon [ "You wear the ", e^.sing, " on your ", pp s, "." ]


getDesigClothSlot :: Ent -> Cloth -> EqMap -> RightOrLeft -> MudStack (Maybe Slot)
getDesigClothSlot e c em rol
  | c `elem` [NoseC, NeckC, UpBodyC, LowBodyC, FullBodyC, BackC, FeetC] = sorryCantWearThere
  | isRingRol rol && c /= FingerC         = sorryCantWearThere
  | c == FingerC && (not . isRingRol $ rol) = sorryNeedRingRol
  | otherwise = case c of EarC    -> maybe sorryFullEar   (return . Just) (findSlotFromList rEarSlots   lEarSlots)
                          WristC  -> maybe sorryFullWrist (return . Just) (findSlotFromList rWristSlots lWristSlots)
                          FingerC -> maybe (return (Just slotFromRol))
                                          (getEnt >=> sorry slotFromRol)
                                          (em^.at slotFromRol)
                          _       -> undefined -- TODO
  where
    sorryCantWearThere     = outputCon [ "You can't wear a ", e^.sing, " on your ", pp rol, "." ] >> return Nothing
    sorryNeedRingRol       = (mapM_ output . T.lines $ ringHelp) >> return Nothing
    findSlotFromList rs ls = findAvailSlot em $ case rol of R -> rs
                                                            L -> ls
                                                            _ -> patternMatchFail "getDesigClothSlot findSlotFromList" [ showText rol ]
    getSlotFromList rs ls  = head $ case rol of R -> rs
                                                L -> ls
                                                _ -> patternMatchFail "getDesigClothSlot getSlotFromList" [ showText rol ]
    sorryFullEar     = sorryFullClothSlotsOneSide (getSlotFromList rEarSlots   lEarSlots)          >> return Nothing
    sorryFullWrist   = sorryFullClothSlotsOneSide (getSlotFromList rWristSlots lWristSlots)        >> return Nothing
    slotFromRol      = fromRol rol :: Slot
    sorry s e'       = outputCon [ "You're already wearing a ", e'^.sing, " on your ", pp s, "." ] >> return Nothing


getAvailClothSlot :: Cloth -> EqMap -> MudStack (Maybe Slot)
getAvailClothSlot c em = do
    s <- getMobGender 0
    h <- getMobHand   0
    case c of EarC    -> procMaybe $ getEarSlotForGender s `mplus` (getEarSlotForGender . otherGender $ s)
              NoseC   -> procMaybe $ findAvailSlot em noseSlots
              NeckC   -> procMaybe $ findAvailSlot em neckSlots
              WristC  -> procMaybe $ getWristSlotForHand h `mplus` (getWristSlotForHand . otherHand $ h)
              FingerC -> procMaybe =<< getRingSlotForHand h
              _       -> undefined -- TODO
  where
    procMaybe             = maybe (sorryFullClothSlots c >> return Nothing) (return . Just)
    getEarSlotForGender s = findAvailSlot em $ case s of Male   -> lEarSlots
                                                         Female -> rEarSlots
                                                         _      -> patternMatchFail "getAvailClothSlot getEarSlotForGender" [ showText s ]
    getWristSlotForHand h = findAvailSlot em $ case h of RHand  -> lWristSlots
                                                         LHand  -> rWristSlots
                                                         _      -> patternMatchFail "getAvailClothSlot getWristSlotForHand" [ showText h ]
    getRingSlotForHand h  = getMobGender 0 >>= \s ->
        return (findAvailSlot em $ case s of Male   -> case h of
                                                        RHand -> [LRingFS, LIndexFS, RRingFS, RIndexFS, LMidFS, RMidFS, LPinkyFS, RPinkyFS]
                                                        LHand -> [RRingFS, RIndexFS, LRingFS, LIndexFS, RMidFS, LMidFS, RPinkyFS, LPinkyFS]
                                                        _     -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText h ]
                                             Female -> case h of
                                                        RHand -> [LRingFS, LIndexFS, RRingFS, RIndexFS, LPinkyFS, RPinkyFS, LMidFS, RMidFS]
                                                        LHand -> [RRingFS, RIndexFS, LRingFS, LIndexFS, RPinkyFS, LPinkyFS, RMidFS, LMidFS]
                                                        _     -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText h ]
                                             _      -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText s ])


-- Ready weapons:


readyWpn :: Id -> Ent -> EqMap -> Maybe RightOrLeft -> MudStack ()
readyWpn i e em mrol
  | not . isSlotAvail em $ BothHandsS = output "You're already wielding a two-handed weapon."
  | otherwise = maybe (getAvailWpnSlot em) (getDesigWpnSlot e em) mrol >>= \ms ->
                    maybeRet (\s -> getWpn i >>= readyHelper s) ms
  where
    readyHelper s w = case w^.wpnSub of OneHanded -> moveReadiedItem i em s >> outputCon [ "You wield the ", e^.sing, " with your ", pp s, "." ]
                                        TwoHanded -> if all (isSlotAvail em) [RHandS, LHandS]
                                                       then moveReadiedItem i em BothHandsS >> output ("You wield the " <> e^.sing <> " with both hands.")
                                                       else output $ "Both hands are required to weild the " <> e^.sing <> "."


getDesigWpnSlot :: Ent -> EqMap -> RightOrLeft -> MudStack (Maybe Slot)
getDesigWpnSlot e em rol
  | isRingRol rol = sorryNotRing
  | otherwise     = maybe (return (Just . desigSlot $ rol)) (getEnt >=> sorry) $ em^.at (desigSlot rol)
  where
    sorryNotRing = output ("You can't wield a " <> e^.sing <> " with your finger!") >> return Nothing
    sorry e'     = outputCon [ "You're already wielding a ", e'^.sing, " with your ", pp . desigSlot $ rol, "." ] >> return Nothing
    desigSlot    = \case R -> RHandS
                         L -> LHandS
                         _ -> patternMatchFail "getDesigWpnSlot desigSlot" [ showText rol ]


getAvailWpnSlot :: EqMap -> MudStack (Maybe Slot)
getAvailWpnSlot em = getMobHand 0 >>= \h ->
    maybe sorry (return . Just) (findAvailSlot em . map getSlotForHand $ [ h, otherHand h ])
  where
    getSlotForHand h = case h of RHand -> RHandS
                                 LHand -> LHandS
                                 _     -> patternMatchFail "getAvailWpnSlot getSlotForHand" [ showText h ]
    sorry = output "You're already wielding two weapons." >> return Nothing


-- Ready armor:


-----


unready :: Action
unready [] = advise ["unready"] $ "Please specify one or more things to unready, as in " <> dblQuote "unready sword" <> "."
unready rs = hasEq 0 >>= \he -> if not he then dudeYou'reNaked else do
    is <- getEq 0
    (gecrs, miss, rcs) <- resolveEntCoinNames rs (is, mempty)
    mapM_ (procGecrMisPCEq shuffleInvUnready) . zip gecrs $ miss
    unless (null rcs) $ output "You can't unready coins."
    liftIO newLine


shuffleInvUnready :: Inv -> MudStack ()
shuffleInvUnready is = M.filter (`notElem` is) <$> getEqMap 0 >>= updateWS 0 eqTbl >> addToInv is 0 >> descUnready is


descUnready :: Inv -> MudStack ()
descUnready is = mkIdCountBothList is >>= mapM_ descUnreadyHelper
  where
    descUnreadyHelper (i, c, b@(s, _)) = verb i >>= \v ->
        outputCon $ if c == 1
          then [ "You ", v, "the ", s, "." ]
          else [ "You ", v, showText c, " ", mkPlurFromBoth b, "." ]
    verb i = getEnt i >>= getEntType >>= \case
      ClothType -> getCloth i >>= \_ -> return unwearGenericVerb -- TODO
      WpnType   -> return "stop wielding "
      _         -> undefined -- TODO
    unwearGenericVerb = "take off "


mkIdCountBothList :: Inv -> MudStack [(Id, Int, BothGramNos)]
mkIdCountBothList is = getEntBothGramNosInInv is >>= \ebgns ->
    let cs = mkCountList ebgns
    in return (nubBy equalCountsAndBoths . zip3 is cs $ ebgns)
  where
    equalCountsAndBoths (_, c, b) (_, c', b') = c == c' && b == b'


-----


uptime :: Action
uptime [] = (try . output . parse =<< runUptime) >>= eitherRet uptimeExHandler >> liftIO newLine
  where
    runUptime = liftIO . readProcess "uptime" [] $ ""
    parse ut  = let (a, b) = span (/= ',') ut
                    a' = unwords . tail . words $ a
                    b' = dropWhile isSpace . takeWhile (/= ',') . tail $ b
                    c  = (toUpper . head $ a') : tail a'
                in T.concat [ c^.packed, " ", b'^.packed, "." ]
uptime rs = ignore rs >> uptime []


uptimeExHandler :: IOException -> MudStack ()
uptimeExHandler e = logIOEx "uptime" e >> dispGenericErrorMsg


-----


quit :: Action
quit [] = output ("Thanks for playing! See you next time." <> nlt) >> liftIO exitSuccess
quit _  = outputCon [ "Type ", dblQuote "quit", " with no arguments to quit the game.", nlt ]


-- ==================================================
-- Wizard commands:


wizDispCmdList :: Action
wizDispCmdList = dispCmdList (cmdPred . Just $ wizCmdChar)


-----


wizShutdown :: Action
wizShutdown [] = logNotice "wizShutdown" "shutting down" >> liftIO exitSuccess
wizShutdown _  = output $ "Type " <> (dblQuote . prefixWizCmd $ "shutdown") <> " with no arguments to shut down the game server.\n"


-----


wizTime :: Action
wizTime [] = do
    output "At the tone, the time will be..."
    ct <- liftIO getCurrentTime
    zt <- liftIO getZonedTime
    output . formatThat . showText $ ct
    output . formatThat . showText $ zt
    liftIO newLine
  where
    formatThat t = let wordy = T.words t
                       zone  = last wordy
                       date  = head wordy
                       time  = T.init . T.reverse . T.dropWhile (/= '.') . T.reverse . head . tail $ wordy
                   in T.concat [ zone, ": ", date, " ", time ]
wizTime rs = ignore rs >> wizTime []


-----


wizDay :: Action
wizDay [] = liftIO getZonedTime >>= \zt ->
    output $ formatTime defaultTimeLocale "%A %B %d" zt ^.packed <> "\n"
wizDay rs = ignore rs >> wizDay []


-- ==================================================
-- Debug commands:


debugDispCmdList :: Action
debugDispCmdList = dispCmdList (cmdPred . Just $ debugCmdChar)


-----


debugBuffCheck :: Action
debugBuffCheck [] = try buffCheckHelper >>= eitherRet (logAndDispIOEx "wizBuffCheck")
  where
    buffCheckHelper = do
        td      <- liftIO getTemporaryDirectory
        (fn, h) <- liftIO . openTempFile td $ "temp"
        bm      <- liftIO . hGetBuffering $ h
        outputConIndent 2 [ "(Default) buffering mode for temp file ", fn^.packed.to dblQuote, " is ", dblQuote . showText $ bm, ".", nlt ]
        liftIO $ hClose  h >> removeFile fn
debugBuffCheck rs = ignore rs >> debugBuffCheck []


-----


debugDispEnv :: Action
debugDispEnv [] = liftIO getEnvironment >>= dispAssocList >> liftIO newLine
debugDispEnv rs = mapM_ helper rs
  where
    helper r = (dispAssocList . filter grepPair =<< liftIO getEnvironment) >> liftIO newLine
      where
        grepPair = uncurry (||) . over both (^.packed.to grep)
        grep     = (r `T.isInfixOf`)


-----


debugLog :: Action
debugLog [] = get >>= replicateM_ 2 . void . liftIO . forkIO . void . runStateInIORefT heavyLogging
  where
    heavyLogging = liftIO myThreadId >>= \i ->
        replicateM_ 10000 . logNotice "debugLog" $ "Logging from " ++ show i
debugLog rs = ignore rs >> debugLog []


------


debugThrow :: Action
debugThrow [] = liftIO . throwIO $ DivideByZero
debugThrow rs = ignore rs >> debugThrow []
