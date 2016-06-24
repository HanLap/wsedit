{-# LANGUAGE LambdaCase #-}

module WSEdit.Control.Selection
    ( initMark
    , ifMarked
    , deleteSelection
    , copy
    , paste
    , indentSelection
    , unindentSelection
    ) where


import Control.Monad.IO.Class   (liftIO)
import Control.Monad.RWS.Strict (ask, get, put)
import Data.List                (stripPrefix)
import Data.Maybe               (fromJust, isJust, fromMaybe)
import System.Directory         (getHomeDirectory)
import System.Hclip             (getClipboard, setClipboard)

import WSEdit.Control.Base      ( alterBuffer, alterState, moveCursor
                                , refuseOnReadOnly
                                )
import WSEdit.Data              ( EdConfig (tabWidth)
                                , EdState (cursorPos, edLines, markPos
                                          , replaceTabs
                                          )
                                , WSEdit
                                , clearMark, delSelection, getMark, getCursor
                                , getSelection, setMark, setStatus
                                )
import WSEdit.Util              (checkClipboardSupport, mayReadFile)

import qualified WSEdit.Buffer as B



-- | Throw down the mark at the current cursor position, if it is not placed
--   somewhere else already.
initMark :: WSEdit ()
initMark = alterState
         $ getMark >>= \case
                Nothing -> getCursor >>= setMark
                _       -> return ()



-- | Executes the first action if the user has selected text (Shift+Movement),
--   or the second one if not.
ifMarked :: WSEdit a -> WSEdit a -> WSEdit a
ifMarked x y = do
    b <- isJust . markPos <$> get
    if b
       then x
       else y



-- | Delete the selected text.
deleteSelection :: WSEdit ()
deleteSelection = alterBuffer $ do
    _ <- delSelection
    clearMark



-- | Copy the text in the selection to the clipboard.
copy :: WSEdit ()
copy = refuseOnReadOnly
     $ getSelection >>= \case
            Nothing -> setStatus "Warning: nothing selected."
            Just s  -> do
                b <- liftIO checkClipboardSupport

                if b
                   then do
                        liftIO $ setClipboard s

                        setStatus $ "Copied "
                                 ++ show (length $ lines s)
                                 ++ " lines ("
                                 ++ show (length s)
                                 ++ " chars) to system clipboard."

                   else do
                        liftIO $ do
                            h <- getHomeDirectory
                            writeFile (h ++ "/.wsedit-clipboard") s

                        setStatus $ "Copied "
                                 ++ show (length $ lines s)
                                 ++ " lines ("
                                 ++ show (length s)
                                 ++ " chars) to editor clipboard."




-- | Paste the clipboard contents to the cursor position.
paste :: WSEdit ()
paste = alterBuffer $ do
    b <- liftIO checkClipboardSupport

    c1 <- liftIO
        $ if b
             then getClipboard
             else do
                    h <- getHomeDirectory
                    fromMaybe "" <$> mayReadFile (h ++ "/.wsedit-clipboard")

    if c1 == ""
       then setStatus $ if b
                           then "Warning: System clipboard is empty."
                           else "Warning: Editor clipboard is empty."

       else do
            let c = lines c1
            s <- get

            put $ s     -- Arcane buffer magic incoming...
                { edLines =
                    if length c == 1
                       then B.withCurr (\l -> take (cursorPos s - 1) l
                                           ++ head c
                                           ++ drop (cursorPos s - 1) l
                                       )
                          $ edLines s

                       else B.withCurr (last c ++ drop (cursorPos s - 1)
                                                       (B.curr $ edLines s)
                                       )
                          $ flip (foldl (flip B.insertLeft))
                                 (drop 1 $ init c)
                          $ B.withCurr (\l -> take (cursorPos s - 1) l
                                           ++ head c
                                       )
                          $ edLines s
                }

            if length c > 1
               then moveCursor 0 $ length (last c) - length (head c)
               else moveCursor 0 $ length c1

            setStatus $ "Pasted "
                     ++ show (length c)
                     ++ " lines ("
                     ++ show (length c1)
                     ++ if b
                           then " chars) from system clipboard."
                           else " chars) from editor clipboard."



-- | Indent the currently selected area using the current tab width and
--   replacement settings.
indentSelection :: WSEdit ()
indentSelection = alterBuffer $ do
    getMark >>= \case
       Nothing      -> return ()
       Just (sR, _) -> do
            s <- get
            c <- ask
            (cR, _) <- getCursor

            let
                ind = if replaceTabs s
                         then replicate (tabWidth c) ' '
                         else "\t"

            put $ s { edLines =
                        case compare sR cR of
                             LT -> B.withCurr            (ind ++)
                                 $ B.withNLeft (cR - sR) (ind ++)
                                 $ edLines s

                             EQ -> B.withCurr (ind ++)
                                 $ edLines s

                             GT -> fromJust
                                 $ B.withCurr             (ind ++)
                                 $ B.withNRight (sR - cR) (ind ++)
                                 $ edLines s
                     }



-- | Unindent the currently selected area using the current tab width and
--   replacement settings.
unindentSelection :: WSEdit ()
unindentSelection = alterBuffer $ do
    getMark >>= \case
       Nothing      -> return ()
       Just (sR, _) -> do
            s <- get
            c <- ask
            (cR, _) <- getCursor

            let
                ind = if replaceTabs s
                         then replicate (tabWidth c) ' '
                         else "\t"

            put $ s { edLines =
                        case compare sR cR of
                             LT -> B.withCurr            (unindent ind)
                                 $ B.withNLeft (cR - sR) (unindent ind)
                                 $ edLines s

                             EQ -> fromJust
                                 $ B.withCurr (unindent ind)
                                 $ edLines s

                             GT -> B.withCurr             (unindent ind)
                                 $ B.withNRight (sR - cR) (unindent ind)
                                 $ edLines s
                     }
    where
        unindent :: String -> String -> String
        unindent prf ln = fromMaybe ln
                        $ stripPrefix prf ln
