{-# LANGUAGE LambdaCase #-}

module WSEdit.Data.Algorithms
    ( getCursor
    , setCursor
    , getMark
    , setMark
    , clearMark
    , getFirstSelected
    , getLastSelected
    , getSelBounds
    , getOffset
    , setOffset
    , setStatus
    , chopHist
    , mapPast
    , alter
    , popHist
    , getSelection
    , delSelection
    , getDisplayBounds
    , getCurrBracket
    , catchEditor
    ) where


import Control.Exception        (SomeException, evaluate, try)
import Control.Monad.IO.Class   (liftIO)
import Control.Monad.RWS.Strict (ask, get, modify, put, runRWST)
import Data.Maybe               (fromMaybe)
import Data.Tuple               (swap)
import Graphics.Vty             ( Vty (outputIface)
                                , displayBounds
                                )
import Safe                     ( fromJustNote, headMay, headNote, initNote
                                , lastNote, tailNote
                                )

import WSEdit.Util              (unlinesPlus, withSnd)

import WSEdit.Data              ( WSEdit
                                , EdConfig (histSize, vtyObj)
                                , EdState ( bracketCache, changed, cursorPos
                                          , edLines, markPos, history
                                          , scrollOffset, status
                                          )
                                )

import qualified WSEdit.Buffer as B



fqn :: String -> String
fqn = ("WSEdit.Data.Algorithms" ++)





-- | Retrieve the current cursor position.
getCursor :: WSEdit (Int, Int)
getCursor = do
    s <- get
    return (B.currPos (edLines s) + 1, cursorPos s)

-- | Set the current cursor position.
setCursor :: (Int, Int) -> WSEdit ()
setCursor (r, c) = do
    s <- get
    put $ s { cursorPos = c
            , edLines   = B.moveTo (r - 1) $ edLines s
            }


-- | Retrieve the current mark position, if it exists.
getMark :: WSEdit (Maybe (Int, Int))
getMark = markPos <$> get


-- | Set the mark to a position.
setMark :: (Int, Int) -> WSEdit ()
setMark p = do
    s <- get
    put $ s { markPos = Just p }

-- | Clear a previously set mark.
clearMark :: WSEdit ()
clearMark = do
    s <- get
    put $ s { markPos = Nothing }



-- | Retrieve the position of the first selected element.
getFirstSelected :: WSEdit (Maybe (Int, Int))
getFirstSelected = fmap fst <$> getSelBounds


-- | Retrieve the position of the last selected element.
getLastSelected :: WSEdit (Maybe (Int, Int))
getLastSelected = fmap snd <$> getSelBounds


-- | Faster combination of 'getFirstSelected' and 'getLastSelected'.
getSelBounds :: WSEdit (Maybe ((Int, Int), (Int, Int)))
getSelBounds =
    getMark >>= \case
        Nothing -> return Nothing
        Just (mR, mC) -> do
            (cR, cC) <- getCursor

            case compare mR cR of
                 LT -> return $ Just ((mR, mC), (cR, cC - 1))
                 GT -> return $ Just ((cR, cC), (mR, mC - 1))
                 EQ ->
                    case compare mC cC of
                         LT -> return $ Just ((mR, mC), (cR, cC - 1))
                         GT -> return $ Just ((cR, cC), (mR, mC - 1))
                         EQ -> return Nothing




-- | Retrieve the current viewport offset (relative to the start of the file).
getOffset :: WSEdit (Int, Int)
getOffset = scrollOffset <$> get

-- | Set the viewport offset.
setOffset :: (Int, Int) -> WSEdit ()
setOffset p = do
    s <- get
    put $ s { scrollOffset = p }



-- | Set the status line's contents.
setStatus :: String -> WSEdit ()
setStatus st = do
    s <- get

    -- Precaution, since lazyness can be quirky sometimes
    st' <- liftIO $ evaluate st

    put $ s { status = st' }



-- | The 'EdState' 'history' is structured like a conventional list, and
--   this is its 'take', with some added 'Maybe'ness.
chopHist :: Int -> Maybe EdState -> Maybe EdState
chopHist n _        | n <= 0 = Nothing
chopHist _ Nothing           = Nothing
chopHist n (Just s)          =
    Just $ s { history = chopHist (n-1) (history s) }

-- | The 'EdState' 'history' is structured like a conventional list, and
--   this is its 'map'.  Function doesn't get applied to the present state
--   though.
mapPast :: (EdState -> EdState) -> EdState -> EdState
mapPast f s =
    case history s of
         Nothing -> s
         Just  h -> s { history = Just $ mapPast f $ f h }



-- | Create an undo checkpoint and set the changed flag.
alter :: WSEdit ()
alter = do
    h <- histSize <$> ask
    modify (\s -> s { history = chopHist h (Just s)
                    , changed = True
                    } )


-- | Restore the last undo checkpoint, if available.
popHist :: WSEdit ()
popHist = modify popHist'

    where
        -- | The 'EdState' 'history' is structured like a conventional list, and
        --   this is its 'tail'.
        popHist' :: EdState -> EdState
        popHist' s = fromMaybe s $ history s



-- | Retrieve the contents of the current selection.
getSelection :: WSEdit (Maybe String)
getSelection = getSelBounds >>= \case
    Nothing                   -> return Nothing
    Just ((sR, sC), (eR, eC)) -> do
        l <- edLines <$> get

        if sR == eR
           then return $ Just
                       $ drop (sC - 1)
                       $ take eC
                       $ snd
                       $ B.pos l

           else
                let
                    lns   = map snd $ B.sub (sR - 1) (eR - 1) l
                    front = drop (sC - 1) $ headNote (fqn "getSelection") lns
                    back  = take  eC      $ lastNote (fqn "getSelection") lns
                in
                    return $ Just
                           $ front
                          ++ "\n"
                          ++ unlinesPlus ( tailNote (fqn "getSelection")
                                         $ initNote (fqn "getSelection")
                                           lns
                                         )
                          ++ (if length lns > 2 then "\n" else "")
                          ++ back



-- | Delete the contents of the current selection from the text buffer.
delSelection :: WSEdit Bool
delSelection = getSelBounds >>= \case
    Nothing                 -> return False
    Just ((_, sC), (_, eC)) -> do
        (mR, mC) <- fromJustNote (fqn "getSelection") <$> getMark
        (cR, cC) <- getCursor

        s <- get

        case compare mR cR of
             EQ -> do
                put $ s { edLines   = B.withCurr (\(b, l) -> (b, take (sC - 1) l
                                                              ++ drop  eC      l
                                                             )
                                                 )
                                    $ edLines s
                        , cursorPos = sC
                        }
                return True

             LT -> do
                put $ s { edLines   = B.withCurr (\(b, l) -> (b, take (mC - 1) l
                                                              ++ drop (cC - 1)
                                                                 ( snd
                                                                 $ B.pos
                                                                 $ edLines s
                                                                 )
                                                             )
                                                 )
                                    $ B.dropLeft (cR - mR)
                                    $ edLines s
                        , cursorPos = sC
                        }
                return True

             GT -> do
                put $ s { edLines   = B.withCurr (\(b, l) -> (b, take (cC - 1)
                                                               ( snd
                                                               $ B.pos
                                                               $ edLines s
                                                               )
                                                              ++ drop (mC - 1) l
                                                             )
                                                 )
                                    $ B.dropRight (mR - cR)
                                    $ edLines s
                        , cursorPos = sC
                        }
                return True



-- | Retrieve the number of rows, colums displayed by vty, including all borders
--   , frames and similar woo.
getDisplayBounds :: WSEdit (Int, Int)
getDisplayBounds = fmap swap (displayBounds . outputIface . vtyObj =<< ask)



-- | Returns the bounds of the brackets the cursor currently resides in.
getCurrBracket :: WSEdit (Maybe ((Int, Int), (Int, Int)))
getCurrBracket = do
    (cR, cC) <- getCursor

    s <- get

    let
        brs1 = concat
             $ drop (cR - 1)
             $ reverse
             $ map fst
             $ bracketCache s

        brs2 = map (withSnd $ const (maxBound, maxBound))
             $ fromMaybe []
             $ fmap snd
             $ headMay
             $ bracketCache s

        brs  = filter ((>= (cR, cC)) . snd)
             $ filter ((<= (cR, cC)) . fst)
             $ brs1 ++ brs2

    return $ headMay brs





-- | Lifted version of 'catch' typed to 'SomeException'.
catchEditor :: WSEdit a -> (SomeException -> WSEdit a) -> WSEdit a
catchEditor a e = do
    c <- ask
    s <- get
    (r, s') <- liftIO $ try (runRWST a c s) >>= \case
                    Right (r, s', _) -> return (r, s')
                    Left  err        -> do
                        (r, s', _) <- runRWST (e err) c s
                        return (r, s')
    put s'
    return r