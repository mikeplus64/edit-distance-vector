{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections   #-}

-- | Description: Calculate differences between vectors.
--
-- This module implements a variation on the Wagner-Fischer algorithm to find
-- the shortest sequences of operations which transformers one vector of values
-- into another.
module Data.Vector.Distance where

import           Control.Arrow ((***))
import           Data.Function
import           Data.List     hiding (delete, insert)
import           Data.Maybe
import           Data.Monoid
import           Data.Vector   (Vector)
import qualified Data.Vector   as V

-- | Operations invoked by the Wagner-Fischer algorithm.
data Params e c = Params
    { equivalent     :: e -> e -> Bool
    -- ^ Are two values equivalent?
    , delete         :: Int -> e -> c
    -- ^ Delete the element at an index.
    , insert         :: Int -> e -> c
    -- ^ Insert an element at an index.
    , substitute     :: Int -> e -> e -> c
    -- ^ Substitute an element at an index.
    , cost           :: c -> Int
    -- ^ Cost of a change.
    , positionOffset :: c -> Int
    -- ^ Positions to advance after a change. E.g. @0@ for a deletion.
    }

-- | Find the least-cost sequence of changes to transform one vector into
-- another.
leastChanges :: Params e c -> [e] -> [e] -> (Int, [c])
leastChanges p ss tt = fmap (catMaybes . reverse) . snd . last $ changes p ss tt

-- | Matrix used to find least cost sequence of changes.
type ChangeMatrix c = [( (Int,Int) , (Int, [Maybe c]) )]

-- | Calculate the complete matrix of changes which transform one sequence of
-- values into another.
changes :: Params e c -> [e] -> [e] -> ChangeMatrix c
changes p@Params{..} ss tt = sortBy (compare `on` fst) f
  where
    f =  [ ((0  ,   0), (0,   [])) ]
         -- Deletes across the top.
      <> [ ((i+1,   0), (1+i, fmap Just s))
         | (i,s) <- items . fmap (\i -> fmap (delete 0) . reverse $ take i ss)
            $ [1..length ss]
         ]
         -- Inserts down the side.
      <> [ ((0  , j+1), (1+j, fmap Just t))
         | (j,t) <- items . fmap reverse . tail . inits $ zipWith insert [0..] tt
         ]
         -- Changes in the middle.
      <> [ ((i+1, j+1), o)
         | (i,s) <- items ss
         , (j,t) <- items tt
         , let o = choose p (i,s) (j,t) f
         ]
    items = zip [0..]

-- | Choose an operation to perform at an /internal/ cell in a 'ChangeMatrix'.
--
-- 'choose' requires that the 'ChangeMatrix' defines values at @(i,j)@,
-- @(i+1,j)@, and @(i, j+1)@ (i.e. the cells to the top-left, top, and left of
-- the cell being determined).
--
-- If the values compared are equal no operation will be performed; otherwise an
-- insertion, deletion, or substitution will be performed, whichever is cheaper.
choose
    :: Params e c
    -> (Int, e) -- ^ \"From\" index and value.
    -> (Int, e) -- ^ \"To\" index and value.
    -> ChangeMatrix c -- ^ Previous changes.
    -> (Int, [Maybe c]) -- ^ Cost and change selected.
choose Params{..} (i,s) (j,t) m =
    let tl    = get m    i    j
        top   = get m    i (1+j)
        left  = get m (1+i)    j
    in if s `equivalent` t
        then (fst tl, Nothing : snd tl)
        else minimumBy (compare `on` fst)
            -- Option 1: perform a deletion.
            [ let c = delete (pos (snd top)) s
                in (cost c +) *** (Just c :) $ top
            -- Option 2: perform an insertion.
            , let c = insert (pos (snd left)) t
                in (cost c +) *** (Just c :) $ left
            -- Option 3: perform a substitution.
            , let c = substitute (pos (snd tl)) s t
                in (cost c +) *** (Just c :) $ tl
            ]
  where
    pos = sum . fmap (maybe 1 positionOffset)
    get :: ChangeMatrix c -> Int -> Int -> (Int, [Maybe c])
    get mat x y = fromMaybe
        (error $ "Unable to get " <> show (x,y) <> " from change matrix")
        (lookup (x,y) mat)
