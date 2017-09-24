{-# LANGUAGE UnicodeSyntax #-}
module Data.FuzzySet.Utils
  ( normalized
  , substr
  , enclosedIn
  ) where

import Data.Char                       ( isAlphaNum, isSpace )
import Data.Text                       ( Text, cons, snoc )
import Prelude.Unicode
import qualified Data.Text             as Text

-- | Normalize the input by
--     * removing non-word characters, except for spaces and commas; and
--     * converting alphabetic characters to lowercase.
normalized ∷ Text → Text
normalized = Text.filter word ∘ Text.toLower
  where
    word ch
      | isAlphaNum ch = True
      | isSpace    ch = True
      | (≡) ','    ch = True
      | otherwise     = False

-- | Return /n/ characters starting from offset /m/ in the input string.
substr ∷ Int  -- ^ Length of the substring
       → Int  -- ^ Character offset
       → Text -- ^ The input string
       → Text -- ^ A substring of length /n/
{-# INLINE substr #-}
substr n m = Text.take n ∘ Text.drop m

-- | Insert the character /ch/ at the beginning and end of the input string.
enclosedIn ∷ Text → Char → Text
{-# INLINE enclosedIn #-}
enclosedIn str ch = ch `cons` str `snoc` ch

