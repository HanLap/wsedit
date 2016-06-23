module Tests.Base
    ( module Test.HUnit
    , defaultObjects
    , assertPretty
    ) where

import Control.Monad
import Data.Algorithm.Diff
import Data.Algorithm.DiffOutput
import Data.Default
import Test.HUnit
import Text.Show.Pretty

import WSEdit.Data
import WSEdit.Keymaps



-- | Default @(EdConfig, EdState)@ for testing.
defaultObjects :: (EdConfig, EdState)
defaultObjects = (mkDefConfig undefined defaultKM, def { fname = "test.file" })



-- | Assertion template.
assertPretty :: (Eq a, Show a) => String -> a -> a -> Assertion
assertPretty pref ex act = unless (ex == act)
                         $ assertFailure
                         $ pref
                        ++ " failed:\n"
                        ++ ppDiff (getGroupedDiff (lines $ ppShow ex) (lines $ ppShow act))
