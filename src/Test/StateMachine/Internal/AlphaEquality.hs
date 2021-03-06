{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE Rank2Types          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeInType          #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Test.StateMachine.Internal.AlphaEquality
-- Copyright   :  (C) 2017, ATS Advanced Telematic Systems GmbH
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Stevan Andjelkovic <stevan@advancedtelematic.com>
-- Stability   :  provisional
-- Portability :  non-portable (GHC extensions)
--
-- This module provides \(\alpha\)-equality for internal commands. This
-- functionality isn't used anywhere in the library, but can be useful
-- for writing
-- <https://github.com/advancedtelematic/quickcheck-state-machine/blob/master/example/src/MutableReference/Prop.hs metaproperties>.
--
-----------------------------------------------------------------------------

module Test.StateMachine.Internal.AlphaEquality
  ( alphaEq
  , alphaEqFork
  ) where

import           Control.Monad
                   (forM)
import           Control.Monad.State
                   (State, get, put, runState)
import           Data.Kind
                   (Type)
import           Data.Singletons.Decide
                   (SDecide)
import           Data.Singletons.Prelude
                   (Proxy(..))

import           Test.StateMachine.Internal.IxMap
                   (IxMap)
import qualified Test.StateMachine.Internal.IxMap as IxM
import           Test.StateMachine.Internal.Types
import           Test.StateMachine.Types

------------------------------------------------------------------------

canonical'
  :: forall (ix :: Type) (cmd :: Signature ix)
  .  SDecide ix
  => IxTraversable cmd
  => HasResponse   cmd
  => IxMap ix IntRef ConstIntRef
  -> [IntRefed cmd]
  -> ([IntRefed cmd], IxMap ix IntRef ConstIntRef)
canonical' im = flip runState im . go
  where
  go :: [IntRefed cmd] -> State (IxMap ix IntRef ConstIntRef) [IntRefed cmd]
  go xs = forM xs $ \(IntRefed cmd ref) -> do
    cmd' <- ifor (Proxy :: Proxy ConstIntRef) cmd $ \ix iref ->
      (IxM.! (ix, iref)) <$> get
    ref' <- case response cmd of
      SResponse    -> return ()
      SReference i -> do
        m <- get
        let ref' = IntRef (Ref $ IxM.size i m) (Pid 0)
        put $ IxM.insert i ref ref' m
        return ref'
    return $ IntRefed cmd' ref'

canonical
  :: forall ix (cmd :: Signature ix)
  .  SDecide ix
  => IxTraversable cmd
  => HasResponse   cmd
  => [IntRefed cmd]
  -> [IntRefed cmd]
canonical = fst . canonical' IxM.empty

canonicalFork
  :: forall ix (cmd :: Signature ix)
  .  SDecide ix
  => IxTraversable cmd
  => HasResponse   cmd
  => Fork [IntRefed cmd]
  -> Fork [IntRefed cmd]
canonicalFork (Fork l p r) = Fork l' p' r'
  where
  (p', im') = canonical' IxM.empty p
  l'        = fst $ canonical' im' l
  r'        = fst $ canonical' im' r

-- | Check if two lists of commands are equal modulo
--   \(\alpha\)-conversion.
alphaEq
  :: forall ix (cmd :: Signature ix)
  .  SDecide ix
  => IxTraversable cmd
  => HasResponse   cmd
  => Eq (IntRefed cmd)
  => [IntRefed cmd]     -- ^ The two
  -> [IntRefed cmd]     -- ^ input lists.
  -> Bool
alphaEq c0 c1 = canonical c0 == canonical c1

-- | Check if two forks of commands are equal modulo
--   \(\alpha\)-conversion.
alphaEqFork
  :: forall ix (cmd :: Signature ix)
  .  SDecide ix
  => IxTraversable cmd
  => HasResponse   cmd
  => Eq (IntRefed  cmd)
  => Fork [IntRefed cmd]  -- ^ The two
  -> Fork [IntRefed cmd]  -- ^ input forks.
  -> Bool
alphaEqFork f1 f2 = canonicalFork f1 == canonicalFork f2
