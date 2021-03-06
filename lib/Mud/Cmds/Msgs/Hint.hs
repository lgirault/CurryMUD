{-# LANGUAGE OverloadedStrings #-}

module Mud.Cmds.Msgs.Hint where

import           Mud.Data.State.MudData
import           Mud.Misc.ANSI
import           Mud.Util.Operators
import           Mud.Util.Quoting
import           Mud.Util.Text

import           Data.Monoid ((<>))
import           Data.Text (Text)
import qualified Data.Text as T

hintHelper :: [Text] -> Text
hintHelper t = quoteWith' (hintANSI, noHintANSI) "Hint:" |<>| T.concat t

specifyFullHelper :: Text -> Text
specifyFullHelper t = parensQuote . prd $ "Note that you must specify the full " <> t

-----

hintABan :: Text
hintABan = specifyFullHelper "name of the PC you wish to ban"

hintABoot :: Text
hintABoot = specifyFullHelper "PC name of the player you wish to boot"

hintAMsg :: Sing -> Text
hintAMsg s = hintHelper [ "the above is a message from ", s, ", a CurryMUD administrator. To reply, type "
                        , colorWith quoteColor $ "admin " <> uncapitalize s <> " msg"
                        , ", where \"msg\" is the message you want to send to ", s, "." ]

hintAPassword :: Text
hintAPassword = specifyFullHelper "PC name of the player whose password you wish to change"

hintASudoer :: Text
hintASudoer = specifyFullHelper "PC name of the player you wish to promote/demote"

-----

hintDisconnect :: Text
hintDisconnect = specifyFullHelper "name of the person you would like to disconnect"

hintGet :: Text
hintGet = hintHelper [ "it appears that you want to remove an object from a container. In that case, please use the \
                       \\"remove\" command. For example, to remove a ring from your sack, type "
                     , colorWith quoteColor "remove ring sack", "." ]

hintMobSay :: Text
hintMobSay = hintHelper [ "when communicating with non-player characters, you may also try the \"ask\" command. For \
                          \example, to ask a city guard about crime, type "
                        , colorWith quoteColor "ask guard crime", "." ]

hintSpiritCmdNotFound :: Text
hintSpiritCmdNotFound =
    let t = "you have died and become a disembodied spirit. As a spirit, the commands that you may use are limited. \
            \Type \"?\" to see a list of the commands available to you."
    in hintHelper . pure $ t

hintSpiritSeeInDark :: Text
hintSpiritSeeInDark = "It's dark here, and yet you can see everything..."

hintUnlink :: Text
hintUnlink = specifyFullHelper "name of the person with whom you would like to unlink"
