{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE StandaloneDeriving #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  MutableReference.Prop
-- Copyright   :  (C) 2017, ATS Advanced Telematic Systems GmbH
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Stevan Andjelkovic <stevan@advancedtelematic.com>
-- Stability   :  provisional
-- Portability :  non-portable (GHC extensions)
--
-----------------------------------------------------------------------------

module MutableReference.Prop where

import           Control.Arrow
                   ((&&&))
import           Control.Monad
                   (void)
import           Data.Char
                   (isSpace)
import           Data.Dynamic
                   (cast)
import           Data.List
                   (isSubsequenceOf)
import qualified Data.Map                                 as M
import           Data.Tree
                   (Tree(Node), unfoldTree)
import           Test.QuickCheck
                   (Property, forAll)
import           Text.ParserCombinators.ReadP
                   (string)
import           Text.Read
                   (choice, lift, parens, readListPrec,
                   readListPrecDefault, readPrec)

import           Test.StateMachine.Internal.AlphaEquality
import           Test.StateMachine.Internal.Parallel
import           Test.StateMachine.Internal.ScopeCheck
import           Test.StateMachine.Internal.Sequential
import           Test.StateMachine.Internal.Types
import           Test.StateMachine.Internal.Utils

import           MutableReference

------------------------------------------------------------------------

prop_genScope :: Property
prop_genScope = forAll
  (fst <$> liftGen gen (Pid 0) M.empty)
  scopeCheck

prop_genForkScope :: Property
prop_genForkScope = forAll
  (liftGenFork gen)
  scopeCheckFork

prop_sequentialShrink :: Property
prop_sequentialShrink = shrinkPropertyHelper (prop_sequential Bug) $ alphaEq
  [ IntRefed New                                (IntRef 0 0)
  , IntRefed (Write (IntRef (Ref 0) (Pid 0)) 5) ()
  , IntRefed (Read  (IntRef (Ref 0) (Pid 0)))   ()
  ]
  . read . (!! 1) . lines

deriving instance Eq (MemStep ConstIntRef resp)

instance Eq (IntRefed MemStep) where
  IntRefed c1 _ == IntRefed c2 _ = Just c1 == cast c2

cheat :: Fork [IntRefed MemStep] -> Fork [IntRefed MemStep]
cheat = fmap (map (\ms -> case ms of
  IntRefed (Write ref _) () -> IntRefed (Write ref 0) ()
  _                         -> ms))

prop_shrinkForkSubseq :: Property
prop_shrinkForkSubseq = forAll
  (liftGenFork gen)
  $ \f@(Fork l p r) ->
    all (\(Fork l' p' r') -> void l' `isSubsequenceOf` void l &&
                             void p' `isSubsequenceOf` void p &&
                             void r' `isSubsequenceOf` void r)
        (liftShrinkFork shrink1 (cheat f))

prop_shrinkForkScope :: Property
prop_shrinkForkScope = forAll
  (liftGenFork gen)
  $ \f -> all scopeCheckFork (liftShrinkFork shrink1 f)

------------------------------------------------------------------------

prop_shrinkForkMinimal :: Property
prop_shrinkForkMinimal = shrinkPropertyHelper (prop_parallel RaceCondition) $ \out ->
  let f = read $ dropWhile isSpace (lines out !! 1)
  in hasMinimalShrink f || isMinimal f
  where
  hasMinimalShrink :: Fork [IntRefed MemStep] -> Bool
  hasMinimalShrink
    = anyTree isMinimal
    . unfoldTree (id &&& liftShrinkFork shrink1)
    where
    anyTree :: (a -> Bool) -> Tree a -> Bool
    anyTree p = foldTree (\x ih -> p x || or ih)
      where
      -- `foldTree` is part of `Data.Tree` in later versions of `containers`.
      foldTree :: (a -> [b] -> b) -> Tree a -> b
      foldTree f = go where
        go (Node x ts) = f x (map go ts)

  isMinimal :: Fork [IntRefed MemStep] -> Bool
  isMinimal xs = any (alphaEqFork xs) minimal

  minimal :: [Fork [IntRefed MemStep]]
  minimal  = minimal' ++ map mirrored minimal'
    where
    minimal' = [ Fork [w0, IntRefed (Read var) ()]
                      [IntRefed New var]
                      [w1]
               | w0 <- writes
               , w1 <- writes
               ]

    mirrored :: Fork a -> Fork a
    mirrored (Fork l p r) = Fork r p l

    var    = IntRef 0 0
    writes = [IntRefed (Write var 0) (), IntRefed (Inc var) ()]

instance Read (IntRefed MemStep) where
  readPrec = parens $ choice
    [ IntRefed <$> parens (New <$ key "New") <*> readPrec
    , IntRefed <$>
        parens (Read <$ key "Read" <*> readPrec) <*> readPrec
    , IntRefed <$>
        parens (Write <$ key "Write" <*> readPrec <*> readPrec) <*> readPrec
    , IntRefed <$>
        parens (Inc <$ key "Inc" <*> readPrec) <*> readPrec
    ]
    where
    key s = lift (string s)

  readListPrec = readListPrecDefault
