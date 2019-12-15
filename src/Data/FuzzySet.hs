{-# LANGUAGE RecordWildCards #-}

-- |
--
-- Module      : Data.FuzzySet
-- Copyright   : (c) 2017-2019 Johannes Hildén
-- License     : BSD3
-- Maintainer  : hildenjohannes@gmail.com
-- Stability   : experimental
-- Portability : GHC
--
-- A fuzzy string set data structure for approximate string matching. This
-- implementation is based on the Python and JavaScript libraries with the same
-- name:
--
--   * [JavaScript version](http://glench.github.io/fuzzyset.js/)
--   * [Python version](https://github.com/axiak/fuzzyset)

module Data.FuzzySet
    (
    -- * How to use
    -- $howto

    -- * Types
      FuzzySet

    -- * API

    -- ** Initializing
    , mkSet
    , defaultSet
    , fromList

    -- ** Adding
    , add
    , addToSet
    , addMany

    -- ** Retrieving
    , get
    , getWithMinScore
    , getOne

    -- ** Inspecting
    , size
    , isEmpty
    , values
    ) where

import Data.Default (Default, def)
import Data.FuzzySet.Internal
import Data.FuzzySet.Types
import Data.FuzzySet.Util
import Data.HashMap.Strict (HashMap, elems, insert)
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Vector (snoc)
import qualified Data.FuzzySet.Util as Util
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Text as Text
import qualified Data.Vector as Vector


-- | Initialize a 'FuzzySet'.
--
mkSet
    :: Int
    -- ^ Lower bound on gram sizes to use (inclusive)
    -> Int
    -- ^ Upper bound on gram sizes to use (inclusive)
    -> Bool
    -- ^ Whether or not to use the [Levenshtein distance](https://people.cs.pitt.edu/~kirk/cs1501/Pruhs/Spring2006/assignments/editdistance/Levenshtein%20Distance.htm)
    -- to determine the score
    -> FuzzySet
    -- ^ An empty fuzzy string set
mkSet =
    FuzzySet mempty mempty mempty


-- | A 'FuzzySet' with the following field values:
--
-- > { gramSizeLower  = 2
-- > , gramSizeUpper  = 3
-- > , useLevenshtein = True
-- > , exactSet       = empty
-- > , matchDict      = empty
-- > , items          = empty
-- > }
--
defaultSet :: FuzzySet
defaultSet =
    mkSet 2 3 True


-- | See 'defaultSet'.
--
instance Default FuzzySet where
    def = defaultSet


-- | Try to match a string against the entries in the set, and return a list of
-- all results with a score greater than or equal to the specified minimum score
-- (i.e., the first argument). The results are ordered by similarity score, with
-- the closest match first.
--
getWithMinScore
    :: Double
    -- ^ A minimum score
    -> FuzzySet
    -- ^ The fuzzy string set to compare the string against
    -> Text
    -- ^ The lookup query
    -> [( Double, Text )]
    -- ^ A list of results (score and matched value)
getWithMinScore
      minScore
      set@FuzzySet{ gramSizeLower = lower, gramSizeUpper = upper, .. }
      value =
    case key `HashMap.lookup` exactSet of
        Just match ->
            [( 1, match )]

        Nothing ->
            sizes
                |> fmap (getMatches set key minScore)
                |> find (not . null)
                |> fromMaybe []
  where
    key = Text.toLower value
    sizes = reverse (enumFromTo lower upper)


-- | Try to match the given string against the entries in the set, using a
-- minimum score of 0.33. Return a list of results ordered by similarity score,
-- with the closest match first.
--
get :: FuzzySet -> Text -> [( Double, Text )]
get =
    getWithMinScore 0.33


-- | Try to match the given string against the entries in the set, and return
-- the closest match, if one is found.
--
getOne :: FuzzySet -> Text -> Maybe Text
getOne fuzzySet value =
    case fuzzySet `get` value of
        [] ->
            Nothing

        head : _ ->
            Just (snd head)


-- | Add an entry to the set, or do nothing if a key identical to the provided
--   value already exists in the set.
--
add
    :: FuzzySet
    -- ^ Set to add the string to
    -> Text
    -- ^ The new entry
    -> FuzzySet
    -- ^ An updated set
add fuzzySet =
    fst . addToSet fuzzySet


-- | Add an entry, unless it is already present in the set. A pair is returned
-- with the new set and a boolean which denotes whether or not anything was
-- inserted.
--
addToSet
    :: FuzzySet
    -- ^ Fuzzy string set to add the entry to
    -> Text
    -- ^ The new entry
    -> ( FuzzySet, Bool )
    -- ^ The updated set and a boolean, which will be 'True' if, and only if,
    -- the value was not already in the set
addToSet set@FuzzySet{ gramSizeLower = lower, gramSizeUpper = upper, .. } value
    | key `elem` exactSet =
        ( set, False )
    | otherwise =
        ( newSet |> updateExactSet value, True )
  where
    newSet = foldr addSize set (enumFromTo lower upper)
    key = Text.toLower value

    addSize :: Int -> FuzzySet -> FuzzySet
    addSize gramSize FuzzySet{..} =
        let
            item = FuzzySetItem (elems grams |> Util.norm) key
        in
        FuzzySet{ items = items |> insert gramSize (itemVector `snoc` item)
                , matchDict = grams |> HashMap.foldrWithKey updateDict matchDict
                , ..  }
      where
        updateDict gram count =
            let
                info = GramInfo (Vector.length itemVector) count
            in
            HashMap.alter (\maybeInfos -> Just $ info : fromMaybe [] maybeInfos) gram

        itemVector =
            items
                |> HashMap.lookup gramSize
                |> fromMaybe Vector.empty
        grams =
            gramMap key gramSize

    updateExactSet :: Text -> FuzzySet -> FuzzySet
    updateExactSet value FuzzySet{..} =
        FuzzySet{ exactSet = exactSet |> insert key value
                , .. }


-- | Add a list of entries to the set, all in one go.
--
-- @addMany = foldr (flip add)@
--
addMany :: FuzzySet -> [Text] -> FuzzySet
addMany =
    foldr (flip add)


-- | Create a fuzzy string set from a list of entries.
--
-- @fromList = addMany defaultSet@
--
fromList :: [Text] -> FuzzySet
fromList =
    addMany defaultSet


-- | Return the number of entries in the set.
--
-- >>> size (defaultSet `add` "map" `add` "cap")
-- 2
--
size :: FuzzySet -> Int
size =
    HashMap.size . exactSet


-- | Return a boolean indicating whether the set is empty.
--
-- >>> isEmpty (fromList [])
-- True
-- >>> isEmpty $ fromList ["Aramis", "Porthos", "Athos"]
-- False
--
isEmpty :: FuzzySet -> Bool
isEmpty =
    HashMap.null . exactSet


-- | Return the elements of the set. This function is the inverse of 'fromList'.
-- That is; @values ∘ fromList ≡ id@.
--
-- >>> values (fromList ["bass", "craze", "space", "lace", "daze", "haze", "ace", "maze"])
-- ["space","daze","bass","maze","ace","craze","lace","haze"]
--
values :: FuzzySet -> [Text]
values =
    elems . exactSet
