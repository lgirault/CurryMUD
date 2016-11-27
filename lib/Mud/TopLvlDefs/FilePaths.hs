{-# LANGUAGE OverloadedStrings #-}

module Mud.TopLvlDefs.FilePaths where

import System.Directory (getHomeDirectory)
import System.FilePath ((<.>), (</>), pathSeparator)


type HomeDir     = FilePath
type FilePathFun = HomeDir -> FilePath


mkMudFilePath :: FilePathFun -> IO FilePath
mkMudFilePath = flip fmap getHomeDirectory


under :: FilePathFun -> FilePath -> HomeDir -> FilePath
under f fp hd = f hd </> fp


-- ==================================================
-- Directories:


mudDirFun :: FilePathFun
mudDirFun = (</> "CurryMUD")


dbDirFun, logDirFun, persistDirFun, resDirFun :: FilePathFun
dbDirFun      = under mudDirFun "db"
logDirFun     = under mudDirFun "logs"
persistDirFun = under mudDirFun "persist"
resDirFun     = under mudDirFun "res"


helpDirFun, miscDirFun, raceDirFun, titleDirFun :: FilePathFun
helpDirFun  = under resDirFun "help"
miscDirFun  = under resDirFun "misc"
raceDirFun  = under resDirFun "races"
titleDirFun = under resDirFun "titles"


adminHelpDirFun, plaHelpDirFun, rootHeplFileFun :: FilePathFun
adminHelpDirFun = under helpDirFun "admin"
plaHelpDirFun   = under helpDirFun "pla"
rootHeplFileFun = under helpDirFun "root"


plaHelpCmdsDirFun, plaHelpTopicsDirFun :: FilePathFun
plaHelpCmdsDirFun   = under plaHelpDirFun "cmds"
plaHelpTopicsDirFun = under plaHelpDirFun "topics"


adminHelpCmdsDirFun, adminHelpTopicsDirFun :: FilePathFun
adminHelpCmdsDirFun   = under adminHelpDirFun "cmds"
adminHelpTopicsDirFun = under adminHelpDirFun "topics"


-- ==================================================
-- Log files:


bugLogFileFun, errorLogFileFun, loggingExLogFileFun, noticeLogFileFun, typoLogFileFun :: FilePathFun
bugLogFileFun       = under logDirFun $ "bug"                      <.> "log"
errorLogFileFun     = under logDirFun $ "error"                    <.> "log"
loggingExLogFileFun = under logDirFun $ "logging thread exception" <.> "log"
noticeLogFileFun    = under logDirFun $ "notice"                   <.> "log"
typoLogFileFun      = under logDirFun $ "typo"                     <.> "log"


-- ==================================================
-- Persistence files:


armTblFile, chanTblFile, clothTblFile, coinsTblFile, conTblFile, corpseTblFile, entTblFile, eqTblFile, foodTblFile, hostTblFile, invTblFile, mobTblFile, objTblFile, pausedEffectsTblFile, pcSingTblFile, pcTblFile, plaTblFile, rmTblFile, rmTeleNameTblFile, rndmNamesMstrTblFile, teleLinkMstrTblFile, typeTblFile, vesselTblFile, wpnTblFile, writableTblFile :: FilePath
armTblFile           = "armTbl"           <.> "json"
chanTblFile          = "chanTbl"          <.> "json"
clothTblFile         = "clothTbl"         <.> "json"
coinsTblFile         = "coinsTbl"         <.> "json"
conTblFile           = "conTbl"           <.> "json"
corpseTblFile        = "corpseTbl"        <.> "json"
entTblFile           = "entTbl"           <.> "json"
eqTblFile            = "eqTbl"            <.> "json"
foodTblFile          = "foodTbl"          <.> "json"
hostTblFile          = "hostTbl"          <.> "json"
invTblFile           = "invTbl"           <.> "json"
mobTblFile           = "mobTbl"           <.> "json"
objTblFile           = "objTbl"           <.> "json"
pausedEffectsTblFile = "pausedEffectsTbl" <.> "json"
pcSingTblFile        = "pcSingTbl"        <.> "json"
pcTblFile            = "pcTbl"            <.> "json"
plaTblFile           = "plaTbl"           <.> "json"
rmTblFile            = "rmTbl"            <.> "json"
rmTeleNameTblFile    = "rmTeleNameTbl"    <.> "json"
rndmNamesMstrTblFile = "rndmNamesMstrTbl" <.> "json"
teleLinkMstrTblFile  = "teleLinkMstrTbl"  <.> "json"
typeTblFile          = "typeTbl"          <.> "json"
vesselTblFile        = "vesselTbl"        <.> "json"
wpnTblFile           = "wpnTbl"           <.> "json"
writableTblFile      = "writableTbl"      <.> "json"


-- ==================================================
-- The database file:


dbFileFun :: FilePathFun
dbFileFun = under dbDirFun $ "CurryMUD" <.> "sqlite3"


-- ==================================================
-- Misc. files:


aboutFileFun, cowbyeFileFun, descRulesFileFun, motdFileFun, rndmNamesFileFun, uptimeFileFun :: FilePathFun
aboutFileFun     = under miscDirFun "about"
cowbyeFileFun    = under miscDirFun "cowbye"
descRulesFileFun = under miscDirFun "descRules"
motdFileFun      = under miscDirFun "motd"
rndmNamesFileFun = under miscDirFun "randomnames"
uptimeFileFun    = under mudDirFun  "uptime"


profanitiesFileFun :: FilePathFun
profanitiesFileFun = under miscDirFun "profanities"


-- ==================================================
-- Dictionaries:


drive :: Char
drive = pathSeparator


-- "words" - a standard file on all Unix and Unix-like operating systems - is simply a newline-delimited list of
-- dictionary words. Change the path if necessary, or set to "Nothing" if the words file is unavailable.
wordsFile :: Maybe FilePath
wordsFile = Just $ drive : "usr" </> "share" </> "dict" </> "words"


-- In addition to the words file, Mac OS X ships with a dictionary of proper names. Set to "Nothing" if this file is
-- unavailable on your system.
propNamesFile :: Maybe FilePath
propNamesFile = Just $ drive : "usr" </> "share" </> "dict" </> "propernames"
