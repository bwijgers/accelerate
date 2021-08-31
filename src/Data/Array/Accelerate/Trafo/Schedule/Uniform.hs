{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PatternGuards       #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE ViewPatterns        #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_HADDOCK hide #-}
-- |
-- Module      : Data.Array.Accelerate.Trafo.Operation.Substitution
-- Copyright   : [2012..2020] The Accelerate Team
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <trevor.mcdonell@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Data.Array.Accelerate.Trafo.Schedule.Uniform (
) where

import Prelude hiding (read)

import Data.Array.Accelerate.AST.Idx
import Data.Array.Accelerate.AST.IdxSet (IdxSet)
import qualified Data.Array.Accelerate.AST.IdxSet           as IdxSet
import Data.Array.Accelerate.AST.Var
import Data.Array.Accelerate.AST.LeftHandSide
import Data.Array.Accelerate.AST.Schedule.Uniform
import Data.Array.Accelerate.AST.Environment
import qualified Data.Array.Accelerate.AST.Partitioned      as C
import Data.Array.Accelerate.Analysis.Match                 ( (:~:)(..) )
import Data.Array.Accelerate.Trafo.Var
import Data.Array.Accelerate.Trafo.Substitution
import Data.Array.Accelerate.Trafo.Exp.Substitution
import Data.Array.Accelerate.Trafo.Operation.Substitution   (strengthenArrayInstr, reindexVar, reindexVars)
import Data.Array.Accelerate.Representation.Array
import Data.Array.Accelerate.Representation.Type
import Data.Array.Accelerate.Type
import Data.Array.Accelerate.Error
import Data.Kind
import Data.Maybe
import Data.List
import qualified Data.Set                               as S
import GHC.Stack

instance IsExecutableAcc exe => Sink' (UniformSchedule exe) where
  weaken' _ Return                        = Return
  weaken' k (Alet lhs b s)                
    | Exists lhs' <- rebuildLHS lhs   = Alet lhs' (weaken k b) (weaken' (sinkWithLHS lhs lhs' k) s)
  weaken' k (Effect effect s)         = Effect (weaken' k effect) (weaken' k s)
  weaken' k (Acond cond true false s) = Acond (weaken k cond) (weaken' k true) (weaken' k false) (weaken' k s)
  weaken' k (Awhile io f input s)     = Awhile io (weaken k f) (mapTupR (weaken k) input) (weaken' k s)
  weaken' k (Fork s1 s2)              = Fork (weaken' k s1) (weaken' k s2)

instance IsExecutableAcc exe => Sink (UniformScheduleFun exe) where
  weaken k (Slam lhs f)
    | Exists lhs' <- rebuildLHS lhs = Slam lhs' $ weaken (sinkWithLHS lhs lhs' k) f
  weaken k (Sbody s)    = Sbody $ weaken' k s

instance Sink Binding where
  weaken k (Compute e)         = Compute $ mapArrayInstr (weaken k) e
  weaken _ (NewSignal)         = NewSignal
  weaken _ (NewRef r)          = NewRef r
  weaken k (Alloc shr tp size) = Alloc shr tp $ mapTupR (weaken k) size
  weaken _ (Use tp buffer)     = Use tp buffer
  weaken k (Unit var)          = Unit $ weaken k var
  weaken k (RefRead ref)       = RefRead $ weaken k ref

instance IsExecutableAcc exe => Sink' (Effect exe) where
  weaken' k (Exec exe) = Exec $ runIdentity $ reindexExecPartial (weakenReindex k) exe
  weaken' k (SignalAwait vars) = SignalAwait $ map (weaken k) vars
  weaken' k (SignalResolve vars) = SignalResolve $ map (weaken k) vars
  weaken' k (RefWrite ref value) = RefWrite (weaken k ref) (weaken k value)

{-
-- * Compilation from PartitionedAcc to UniformSchedule
data FutureValue senv t
  = Future (BaseVar senv (Ref t)) (BaseVar senv Signal)
  | Ready (BaseVar senv t)

weakenFutureValue :: senv :> senv' -> FutureValue senv t -> FutureValue senv' t
weakenFutureValue k (Future ref sig) = Future (weaken k ref) (weaken k sig)
weakenFutureValue k (Ready var)      = Ready (weaken k var)

data SignalInfo senv t where
  -- Bool denotes whether the signal was already waited on.
  SignalImplies :: Bool -> [Idx senv Signal] -> SignalInfo senv Signal
  -- The SignalResolver resolves the given Signal
  SignalResolvesTo :: Idx senv Signal -> SignalInfo senv SignalResolver
  -- Used for bindings in the environment which are not a signal, or signal which don't have any implications linked to it
  SignalNone    :: SignalInfo senv t

type SignalEnv senv = Env (SignalInfo senv) senv
-}

data Strengthen env env' where
  StrengthenId :: Strengthen env env
  StrengthenSucc :: Strengthen env env' -> Strengthen (env, t) env'

strengthenIdx :: Strengthen env env' -> env :?> env'
strengthenIdx StrengthenId       idx           = Just idx
strengthenIdx (StrengthenSucc k) (SuccIdx idx) = strengthenIdx k idx
strengthenIdx (StrengthenSucc _) ZeroIdx       = Nothing

{-
strengthenSignalInfo :: Strengthen senv senv' -> SignalInfo senv t -> SignalInfo senv' t
strengthenSignalInfo _ SignalNone          = SignalNone
strengthenSignalInfo k (SignalImplies r i) = SignalImplies r $ mapMaybe (strengthenIdx k) i

strengthenSignalEnv :: forall senv senv'. Strengthen senv senv' -> SignalEnv senv -> SignalEnv senv'
strengthenSignalEnv StrengthenId = id
strengthenSignalEnv k = go k
  where
    go :: forall senv1. Strengthen senv1 senv' -> Env (SignalInfo senv) senv1 -> SignalEnv senv'
    go StrengthenId env = mapEnv (strengthenSignalInfo k) env
    go (StrengthenSucc k') (Push env _) = go k' env

weakenSignalInfo :: senv :> senv' -> SignalInfo senv t -> SignalInfo senv' t
weakenSignalInfo _ SignalNone          = SignalNone
weakenSignalInfo k (SignalImplies r i) = SignalImplies r $ map (k >:>) i

weakenSignalEnv :: senv :> senv' -> SignalEnv senv -> Env (SignalInfo senv') senv
weakenSignalEnv k = mapEnv (weakenSignalInfo k)
-}
{-
-- A list of resolved signals (which we already awaited on),
-- and an environment mapping the ground variables to future values.
data FEnv senv genv = FEnv
  -- A list of signals we waited on and the last signal we resolved. This is used to build `SignalImplies` we waiting on a next signal.
  -- Note that we only store one last resolved signal, as we create a chain of resolved signals in the SignalEnv.
  { fenvAwaitedSignals :: [Idx senv Signal]
  -- Set of implications between signal, denoting that some signal will already be resolved when waiting on some other signal.
  , fenvSignalInfo :: SignalEnv senv
  -- Mapping from the ground environment (as used in PartitionedAcc) to the new environment
  , fenvGround     :: Env (FutureValue senv) genv
  }
  -}

{-
-- Returns a new environment, which contains the information that this signal (and possibly others)
-- are resolved (have been waited on). Also returns a Bool denoting whether we should explicitly wait
-- on this signal. I.e., when it returns False, the signal was already previously waited on (possibly
-- indirectly through some other signal), so we don't have to wait on it again.
awaitSignal :: forall senv genv. Idx senv Signal -> FEnv senv genv -> (FEnv senv genv, Bool)
awaitSignal idx fenv = (fenv', shouldWait)
  where
    (signalEnv, shouldWait) = go True idx (fenvSignalInfo fenv)
    fenv' = fenv{ fenvAwaitedSignals = if shouldWait then idx : fenvAwaitedSignals fenv else fenvAwaitedSignals fenv, fenvSignalInfo = signalEnv }

    go :: Bool -> Idx senv Signal -> Env (SignalInfo senv) senv -> (Env (SignalInfo senv) senv, Bool)
    go direct idx' env = (foldr (\ix env' -> fst $ go False ix env') env' implied, shouldWait')
      where
        (env', (implied, shouldWait')) = prjUpdate' f idx' env
        f :: SignalInfo senv Signal -> (SignalInfo senv Signal, ([Idx senv Signal], Bool))
        f SignalNone              = (SignalImplies True [], ([], True))
        f (SignalImplies False i) = (SignalImplies True i , (i , True))
        f (SignalImplies True  i) = (SignalImplies True i , ([], False))

awaitSignals :: [Idx senv Signal] -> FEnv senv genv -> (FEnv senv genv, [Idx senv Signal])
awaitSignals signals fenv = (foldr (\idx fenv' -> fst $ awaitSignal idx fenv') fenv signals, minimal)
  where
    minimal = minimalAwaitSignals fenv signals

-- Computes the transitive closure of the 'implies' relation on signals.
-- Stops the descend at signals in 'stopAt'.
signalTransitiveClosure :: forall senv genv. S.Set (Idx senv Signal) -> Idx senv Signal -> FEnv senv genv -> S.Set (Idx senv Signal)
signalTransitiveClosure stopAt idx fenv = go idx S.empty
  where
    go :: Idx senv Signal -> S.Set (Idx senv Signal) -> S.Set (Idx senv Signal)
    go idx' visited
      | idx' `S.member` visited = visited
      | idx' `S.member` stopAt = S.insert idx' visited
      | otherwise = case prj' idx' $ fenvSignalInfo fenv of
          SignalImplies False i -> foldr go (S.insert idx' visited) i
          _                     -> S.insert idx' visited

-- Shortens a list of signals, such that awaiting this shorter list implies that all the signals are resolved.
minimalAwaitSignals :: forall senv genv. FEnv senv genv -> [Idx senv Signal] -> [Idx senv Signal]
minimalAwaitSignals fenv signals = map fst $ filter f reachables
  where
    f :: (Idx senv Signal, S.Set (Idx senv Signal)) -> Bool
    f self = any (isImpliedBy self) reachables

    -- 'self' is implied by 'other' if 'self' is in 'otherImplies' and if they do not form a cycle.
    -- In case of a cycle, we say that the lowest index implies the other.
    isImpliedBy :: (Idx senv Signal, S.Set (Idx senv Signal)) -> (Idx senv Signal, S.Set (Idx senv Signal)) -> Bool
    isImpliedBy (self, selfImplies) (other, otherImplies)
      | self == other = False
      | self `S.member` otherImplies
        = if other `S.member` selfImplies then
            -- Cycle. We say that the lowest index implies the other. Thus, 'self' is implied by 'other' if other < self.
            other < self
          else
            -- No cycle. 'self' is implied by 'other'.
            True
      | otherwise = False
    
    reachables :: [(Idx senv Signal, S.Set (Idx senv Signal))]
    reachables = map (\idx -> (idx, signalTransitiveClosure set idx fenv)) signals

    set = S.fromList signals

resolveSignal :: FEnv senv genv -> Idx senv SignalResolver -> FEnv senv genv
resolveSignal fenv resolver
  | SignalResolvesTo signal <- prj' resolver $ fenvSignalInfo fenv =
    let
      (signalEnv, _) = prjReplace' signal (SignalImplies True (fenvAwaitedSignals fenv)) $ fenvSignalInfo fenv
    in
      fenv{ fenvSignalInfo = signalEnv, fenvAwaitedSignals = [signal] }
resolveSignal fenv _ = fenv

resolveSignals :: forall senv genv. FEnv senv genv -> [Idx senv SignalResolver] -> FEnv senv genv
resolveSignals fenv resolvers = case signals of
  []                -> fenv
  (firstSignal : _) -> fenv{ fenvSignalInfo = signalEnv, fenvAwaitedSignals = [firstSignal] }
  where
    signals = mapMaybe findSignal $ nub resolvers

    findSignal :: Idx senv SignalResolver -> Maybe (Idx senv Signal)
    findSignal idx = case prj' idx $ fenvSignalInfo fenv of
      SignalResolvesTo signal -> Just signal
      _ -> Nothing

    signalsWithOthers :: [(Idx senv Signal, [Idx senv Signal])]
    signalsWithOthers = mapWithRemainder (\ix ixs -> (ix, ixs)) signals

    signalEnv = updates' f signalsWithOthers $ fenvSignalInfo fenv

    f others _ = SignalImplies True (others ++ fenvAwaitedSignals fenv)
-}
mapWithRemainder :: forall a b. (a -> [a] -> b) -> [a] -> [b]
mapWithRemainder f = go []
  where
    go :: [a] -> [a] -> [b]
    -- prefix is in reverse order
    go prefix (x : xs) = f x (reverseAppend prefix xs) : go (x : prefix) xs
    go _      []       = []

    -- Reverses the first list and appends it to the second
    reverseAppend :: [a] -> [a] -> [a]
    reverseAppend []     accum = accum
    reverseAppend (x:xs) accum = reverseAppend xs (x : accum)

{-

awaitFuture :: FEnv senv genv -> GroundVars genv t -> (forall senv'. senv :> senv' -> BaseVars senv' t -> UniformSchedule exe senv') -> UniformSchedule exe senv
awaitFuture env1 vars1
  = let (symbols, res) = go env1 vars1
  where
    go :: FEnv senv genv -> GroundVars genv t -> (forall senv'. senv :> senv' -> BaseVars senv' t -> UniformSchedule exe senv') -> ([Var senv Signal], UniformSchedule exe senv)
    go env TupRunit f = ([], f weakenId TupRunit)
    go env (TupRsingle )

prjAwaitFuture :: FEnv senv genv -> GroundVar genv t -> Either (BaseVar env t) (BaseVar env Signal, BaseVar env (Ref t), FEnv (senv, t) genv)
prjAwaitFuture (Push _    (Ready var))         (Var _ ZeroIdx) = Left var
prjAwaitFuture (Push senv (Future signal ref)) (Var _ ZeroIdx) = Right (signal, ref, )
  where
    senv' = mapEnv (weakenFutureValue (weakenSucc weakenId)) senv
    -}
{-
prj' :: Idx env t -> Env f env -> f t
prj' ZeroIdx       (Push _   v) = v
prj' (SuccIdx idx) (Push val _) = prj' idx val
-}

type SyncEnv = PartialEnv Sync

data Sync t where
  SyncRead  :: Sync (Buffer e)
  SyncWrite :: Sync (Buffer e)

instance Eq (Sync t) where
  SyncRead  == SyncRead  = True
  SyncWrite == SyncWrite = True
  _         == _         = False

instance Ord (Sync t) where
  SyncRead < SyncWrite = True
  _        < _         = False

data Acquire genv where
  Acquire :: Modifier m
          -> GroundVar genv (Buffer e)
          -- Returns a signal to wait on before the operation can start.
          -- In case of an input buffer (In), this signal refers to
          -- the last write to the buffer.
          -- In case of a Mut or Out buffer, it refers to all previous
          -- usages of the buffer, both reads and writes. The signal
          -- variable may thus later on be substituted for multiple
          -- variables.
          -- Also provides a SignalResolver which should be resolved
          -- when the operation is finished. Later reads or writes to
          -- this buffer will wait on this signal.
          -> Acquire genv

data ConvertEnv genv fenv fenv' where
  ConvertEnvNil     :: ConvertEnv genv fenv fenv

  ConvertEnvSeq     :: ConvertEnv genv fenv1 fenv2
                    -> ConvertEnv genv fenv2 fenv3
                    -> ConvertEnv genv fenv1 fenv3

  ConvertEnvAcquire :: Acquire genv
                    -> ConvertEnv genv fenv ((fenv, Signal), SignalResolver)

  ConvertEnvFuture  :: GroundVar genv e
                    -> ConvertEnv genv fenv ((fenv, Signal), Ref e)

data PartialDoOutput fenv fenv' t r where
  PartialDoOutputPair     :: PartialDoOutput fenv1 fenv2 t  r
                    -> PartialDoOutput fenv2 fenv3 t' r'
                    -> PartialDoOutput fenv1 fenv3 (t, t') (r, r')

  -- First SignalResolver grants access to the ref, the second grants read access and the
  -- third guarantees that all reads have been finished.
  -- Together they thus grant write access.
  --
  PartialDoOutputUnique   :: fenv' ~ ((((fenv, OutputRef (Buffer t)), SignalResolver), SignalResolver), SignalResolver)
                    => ScalarType t
                    -> PartialDoOutput fenv  fenv' (Buffer t) (((SignalResolver, SignalResolver), SignalResolver), OutputRef (Buffer t))

  -- First SignalResolver grants access to the ref, the second grants read access.
  --
  PartialDoOutputShared   :: fenv' ~ (((fenv, OutputRef (Buffer t)), SignalResolver), SignalResolver)
                    => ScalarType t
                    -> PartialDoOutput fenv  fenv' (Buffer t) ((SignalResolver, SignalResolver), OutputRef (Buffer t))

  -- Scalar values or shared buffers
  PartialDoOutputScalar   :: fenv' ~ ((fenv, OutputRef t), SignalResolver)
                    => ScalarType t
                    -> PartialDoOutput fenv  fenv' t (SignalResolver, OutputRef t)

  PartialDoOutputUnit     :: PartialDoOutput fenv  fenv () ()

partialDoOutputGroundsR :: PartialDoOutput fenv fenv' t r -> GroundsR t
partialDoOutputGroundsR (PartialDoOutputPair out1 out2) = partialDoOutputGroundsR out1 `TupRpair` partialDoOutputGroundsR out2
partialDoOutputGroundsR (PartialDoOutputUnique tp) = TupRsingle $ GroundRbuffer tp
partialDoOutputGroundsR (PartialDoOutputShared tp) = TupRsingle $ GroundRbuffer tp
partialDoOutputGroundsR (PartialDoOutputScalar tp) = TupRsingle $ GroundRscalar tp
partialDoOutputGroundsR PartialDoOutputUnit        = TupRunit

data OutputEnv t r where
  OutputEnvPair :: OutputEnv t  r
                 -> OutputEnv t' r'
                 -> OutputEnv (t, t') (r, r')

  -- The SignalResolvers grant access to the reference, to reading the buffer and writing to the buffer.
  -- The consumer of this buffer is the unique consumer of it, and thus takes ownership (and responsibility to deallocate it).
  OutputEnvUnique :: OutputEnv (Buffer t) (((SignalResolver, SignalResolver), SignalResolver), OutputRef (Buffer t))

  -- The SignalResolvers grant access to the reference and to reading the buffer.
  -- The consumer of this buffer does not get ownership, there may be multiple references to this buffer.
  OutputEnvShared :: OutputEnv (Buffer t) ((SignalResolver, SignalResolver), OutputRef (Buffer t))

  OutputEnvScalar :: ScalarType t -> OutputEnv t (SignalResolver, OutputRef t)

  -- There is no output (unit) or the output variables are reused
  -- with destination-passing-style.
  -- We thus do not need to copy the results manually.
  --
  OutputEnvIgnore :: OutputEnv t ()

data DefineOutput fenv t where
  DefineOutput :: PartialDoOutput fenv fenv' t r
                -> fenv :> fenv'
                -> (forall fenv'' . fenv' :> fenv'' -> BaseVars fenv'' r)
                -> DefineOutput fenv t

defineOutput :: forall fenv t.
                 GroundsR t
              -> Uniquenesses t
              -> DefineOutput fenv t
defineOutput (TupRsingle (GroundRbuffer tp)) (TupRsingle Unique) = DefineOutput env subst value
  where
    env = PartialDoOutputUnique tp

    subst = weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId

    value :: forall fenv''. ((((fenv, OutputRef t), SignalResolver), SignalResolver), SignalResolver) :> fenv'' -> BaseVars fenv'' (((SignalResolver, SignalResolver), SignalResolver), OutputRef t)
    value k = ((TupRsingle (Var BaseRsignalResolver $ k >:> ZeroIdx) `TupRpair` TupRsingle (Var BaseRsignalResolver $ k >:> SuccIdx ZeroIdx)) `TupRpair` TupRsingle (Var BaseRsignalResolver (k >:> SuccIdx (SuccIdx ZeroIdx)))) `TupRpair` TupRsingle (Var (BaseRrefWrite $ GroundRbuffer tp) (k >:> SuccIdx (SuccIdx $ SuccIdx ZeroIdx)))
defineOutput (TupRsingle (GroundRscalar tp)) (TupRsingle Unique) = bufferImpossible tp
defineOutput (TupRsingle (GroundRbuffer tp)) _ = DefineOutput env subst value
  where
    env = PartialDoOutputShared tp

    subst = weakenSucc $ weakenSucc $ weakenSucc weakenId

    value :: forall fenv''. ((((fenv, OutputRef t), SignalResolver), SignalResolver)) :> fenv'' -> BaseVars fenv'' ((SignalResolver, SignalResolver), OutputRef t)
    value k = (TupRsingle (Var BaseRsignalResolver $ k >:> ZeroIdx) `TupRpair` TupRsingle (Var BaseRsignalResolver $ k >:> SuccIdx ZeroIdx)) `TupRpair` TupRsingle (Var (BaseRrefWrite $ GroundRbuffer tp) (k >:> SuccIdx (SuccIdx ZeroIdx)))
defineOutput (TupRsingle (GroundRscalar tp)) _ = DefineOutput env subst value
  where
    env = PartialDoOutputScalar tp

    subst = weakenSucc $ weakenSucc weakenId

    value :: forall fenv''. ((fenv, OutputRef t), SignalResolver) :> fenv'' -> BaseVars fenv'' (SignalResolver, OutputRef t)
    value k = TupRsingle (Var BaseRsignalResolver $ k >:> ZeroIdx) `TupRpair` TupRsingle (Var (BaseRrefWrite $ GroundRscalar tp) (k >:> SuccIdx ZeroIdx))
defineOutput (TupRpair t1 t2) us
  | DefineOutput out1 subst1 value1 <- defineOutput t1 u1
  , DefineOutput out2 subst2 value2 <- defineOutput t2 u2 = DefineOutput (PartialDoOutputPair out1 out2) (subst2 .> subst1) (\k -> value1 (k .> subst2) `TupRpair` value2 k)
  where
    (u1, u2) = pairUniqueness us
defineOutput TupRunit         _                     = DefineOutput PartialDoOutputUnit weakenId (const TupRunit)

writeOutput :: PartialDoOutput fenv fenv' t r -> BaseVars fenv'' r -> BaseVars fenv'' t -> UniformSchedule (Cluster op) fenv''
writeOutput doOutput outputVars valueVars = go doOutput outputVars valueVars Return
  where
    go :: PartialDoOutput fenv fenv' t r -> BaseVars fenv'' r -> BaseVars fenv'' t -> UniformSchedule (Cluster op) fenv'' -> UniformSchedule (Cluster op) fenv''
    go PartialDoOutputUnit _ _ = id
    go (PartialDoOutputPair o1 o2) (TupRpair r1 r2) (TupRpair v1 v2) = go o1 r1 v1 . go o2 r2 v2
    go (PartialDoOutputScalar _) (TupRpair (TupRsingle signal) (TupRsingle ref)) (TupRsingle v)
      = Effect (RefWrite ref v)
      . Effect (SignalResolve [varIdx signal])
    go (PartialDoOutputShared _) (TupRpair (TupRsingle s1 `TupRpair` TupRsingle s2) (TupRsingle ref)) (TupRsingle v)
      = Effect (RefWrite ref v)
      . Effect (SignalResolve [varIdx s1, varIdx s2])
    go (PartialDoOutputUnique _) (TupRpair (TupRpair (TupRsingle s1 `TupRpair` TupRsingle s2) (TupRsingle s3)) (TupRsingle ref)) (TupRsingle v)
      = Effect (RefWrite ref v)
      . Effect (SignalResolve [varIdx s1, varIdx s2, varIdx s3])

data ReEnv genv fenv where
  ReEnvEnd  :: ReEnv genv fenv
  ReEnvSkip :: ReEnv genv fenv -> ReEnv (genv, t) fenv
  ReEnvKeep :: ReEnv genv fenv -> ReEnv (genv, t) (fenv, t)

reEnvIdx :: ReEnv genv fenv -> genv :?> fenv
reEnvIdx (ReEnvKeep _) ZeroIdx = Just ZeroIdx
reEnvIdx (ReEnvKeep r) (SuccIdx ix) = SuccIdx <$> reEnvIdx r ix
reEnvIdx (ReEnvSkip r) (SuccIdx ix) = reEnvIdx r ix
reEnvIdx _             _            = Nothing
{-
data ConvertEnvRead op genv fenv1 where
  ConvertEnvRead :: (UniformSchedule (Cluster op) fenv2 -> UniformSchedule (Cluster op) fenv1)
                 -> (forall fenv3. ReEnv genv fenv2 fenv3 -> ReEnv genv fenv1 fenv3) -- TODO: This doesn't work. We need to assure that genv and fenv are in the same order
                 -> fenv1 :> fenv2
                 -> ConvertEnvRead op genv fenv1
-}
-- Void data type with orphan type argument.
-- Used to mark that a variable of the ground environment is used.
--
data FutureRef fenv t = FutureRef (BaseVar fenv (Ref t))

convertEnvRefs :: forall genv fenv fenv'. ConvertEnv genv fenv fenv' -> PartialEnv (FutureRef fenv') genv
convertEnvRefs env = partialEnvFromList const $ snd $ go weakenId env []
  where
    go :: fenv2 :> fenv' -> ConvertEnv genv fenv1 fenv2 -> [EnvBinding (FutureRef fenv') genv] -> (fenv1 :> fenv', [EnvBinding (FutureRef fenv') genv])
    go k ConvertEnvNil                 accum = (k, accum)
    go k (ConvertEnvSeq e1 e2)         accum = (k1, bs')
      where
        (k2, bs) = go k e2 accum
        (k1, bs') = go k2 e1 bs
    go k (ConvertEnvAcquire _)         accum = (weakenSucc $ weakenSucc k, accum)
    go k (ConvertEnvFuture (Var tp ix)) accum = (weakenSucc $ weakenSucc k, EnvBinding ix (FutureRef $ Var (BaseRref tp) $ k >:> ZeroIdx) : accum)

data Reads exe genv fenv where
  Reads :: ReEnv genv fenv'
        -> (fenv :> fenv')
        -> (UniformSchedule exe fenv' -> UniformSchedule exe fenv)
        -> Reads exe genv fenv

readRefs :: PartialEnv (FutureRef fenv) genv -> Reads exe genv fenv
readRefs PEnd = Reads ReEnvEnd weakenId id
readRefs (PPush env (FutureRef (Var tp idx)))
  | Reads r k f <- readRefs env =
    let
      tp' = case tp of
        BaseRref t -> BaseRground t
        _ -> error "Impossible Ref base type"
      r' = ReEnvKeep r
      k' = weakenSucc' k
      f' = f . Alet (LeftHandSideSingle tp') (RefRead $ Var tp $ k >:> idx)
    in
      Reads r' k' f'
readRefs (PNone env)
  | Reads r k f <- readRefs env = Reads (ReEnvSkip r) k f

convertEnvWeaken :: ConvertEnv genv fenv fenv' -> fenv :> fenv'
convertEnvWeaken ConvertEnvNil = weakenId
convertEnvWeaken (ConvertEnvAcquire _) = weakenSucc (weakenSucc weakenId)
convertEnvWeaken (ConvertEnvFuture _)  = weakenSucc (weakenSucc weakenId)
convertEnvWeaken (ConvertEnvSeq e1 e2) = convertEnvWeaken e2 .> convertEnvWeaken e1

convertEnvSignals :: forall genv fenv fenv'. ConvertEnv genv fenv fenv' -> [Idx fenv' Signal]
convertEnvSignals = snd . flip (go weakenId) []
  where
    go :: fenv2 :> fenv' -> ConvertEnv genv fenv1 fenv2 -> [Idx fenv' Signal] -> (fenv1 :> fenv', [Idx fenv' Signal])
    go k ConvertEnvNil         accum = (k, accum)
    go k (ConvertEnvAcquire _) accum = (weakenSucc $ weakenSucc k, k >:> SuccIdx ZeroIdx : accum)
    go k (ConvertEnvFuture _)  accum = (weakenSucc $ weakenSucc k, k >:> SuccIdx ZeroIdx : accum)
    go k (ConvertEnvSeq e1 e2) accum = go k' e1 accum'
      where
        (k', accum') = go k e2 accum

convertEnvSignalResolvers :: forall genv fenv fenv' fenv''. fenv' :> fenv'' -> ConvertEnv genv fenv fenv' -> [Idx fenv'' SignalResolver]
convertEnvSignalResolvers k1 = snd . flip (go k1) []
  where
    go :: fenv2 :> fenv'' -> ConvertEnv genv fenv1 fenv2 -> [Idx fenv'' SignalResolver] -> (fenv1 :> fenv'', [Idx fenv'' SignalResolver])
    go k ConvertEnvNil         accum = (k, accum)
    go k (ConvertEnvAcquire _) accum = (weakenSucc $ weakenSucc k, k >:> ZeroIdx : accum)
    go k (ConvertEnvFuture _)  accum = (weakenSucc $ weakenSucc k, accum)
    go k (ConvertEnvSeq e1 e2) accum = go k' e1 accum'
      where
        (k', accum') = go k e2 accum

convertEnvReadonlyFromList :: [Exists (GroundVar genv)] -> Exists (ConvertEnv genv fenv)
convertEnvReadonlyFromList []
    = Exists ConvertEnvNil
convertEnvReadonlyFromList [Exists var]
  | Exists e1 <- convertEnvReadonlyVar var
    = Exists e1
convertEnvReadonlyFromList (Exists var:vars)
  | Exists e1 <- convertEnvReadonlyVar var
  , Exists e2 <- convertEnvReadonlyFromList vars
    = Exists $ e1 `ConvertEnvSeq` e2

convertEnvReadonlyVar :: GroundVar genv t -> Exists (ConvertEnv genv fenv)
convertEnvReadonlyVar var@(Var tp _)
  | GroundRbuffer _ <- tp = Exists $ future `ConvertEnvSeq` ConvertEnvAcquire (Acquire In var)
  | otherwise             = Exists future
    where
      future = ConvertEnvFuture var

convertEnvFromList :: [Exists (Var AccessGroundR genv)] -> Exists (ConvertEnv genv fenv) 
convertEnvFromList [] = Exists ConvertEnvNil
convertEnvFromList [Exists var]
  | Exists e1 <- convertEnvVar var
    = Exists e1
convertEnvFromList (Exists var:vars)
  | Exists e1 <- convertEnvVar var
  , Exists e2 <- convertEnvFromList vars
    = Exists $ e1 `ConvertEnvSeq` e2

convertEnvToList :: ConvertEnv genv fenv fenv' -> [Exists (Idx genv)]
convertEnvToList = (`go` [])
  where
    go :: ConvertEnv genv fenv fenv' -> [Exists (Idx genv)] -> [Exists (Idx genv)]
    go ConvertEnvNil = id
    go (ConvertEnvSeq e1 e2) = go e1 . go e2
    go (ConvertEnvAcquire (Acquire _ (Var _ idx))) = (Exists idx :)
    go (ConvertEnvFuture (Var _ idx)) = (Exists idx :)

convertEnvVar :: Var AccessGroundR genv t -> Exists (ConvertEnv genv fenv)
convertEnvVar (Var (AccessGroundRscalar   tp) ix) = Exists $ ConvertEnvFuture $ Var (GroundRscalar tp) ix
convertEnvVar (Var (AccessGroundRbuffer m tp) ix) = Exists $ ConvertEnvFuture var `ConvertEnvSeq` ConvertEnvAcquire (Acquire m var)
  where
    var = Var (GroundRbuffer tp) ix

lhsSignalResolver :: BLeftHandSide SignalResolver fenv (fenv, SignalResolver)
lhsSignalResolver = LeftHandSideSingle BaseRsignalResolver

-- In PartialDeclare, we try to reuse the return address of the computation,
-- if this variable will be returned.
--
data Destination r t where
  DestinationNew   :: Destination r t
  DestinationReuse :: TupleIdx r t -> Destination r t

data TupleIdx s t where
  TupleIdxLeft  :: TupleIdx l t -> TupleIdx (l, r) t
  TupleIdxRight :: TupleIdx r t -> TupleIdx (l, r) t
  TupleIdxSelf  :: TupleIdx t t

data PartialSchedule op genv t where
  PartialDo     :: PartialDoOutput () fenv t r
                -> ConvertEnv genv fenv fenv'
                -> UniformSchedule (Cluster op) fenv'
                -> PartialSchedule op genv t

  -- Returns a tuple of variables. Note that (some of) these
  -- variables may already have been resolved, as they may be
  -- annotated in PartialDeclare. We allow variables to unify,
  -- to prevent additional signals and references to be created.
  --
  PartialReturn :: Uniquenesses t
                -> GroundVars genv t
                -> PartialSchedule op genv t

  -- When both branches use the same buffer variables, the first
  -- branch first gets access to it and can release it (using OutputRelease)
  -- to the second branch.
  -- The ordering in this constructor is thus not symmetric (as opposed to Fork
  -- in UniformSchedule, as the dependency is made explicit there by the use of
  -- signals).
  -- When the left branch has a OutputRelease matching with a InputAcquire from
  -- the second branch (or other matching signals), a new signal will be bound
  -- here.
  -- Note that whereas 'BufferSignals genv' could be derived from the two branches,
  -- it is stored here to avoid recomputing it multiple times, which should mean
  -- that we only compute buffer signals O(n) times instead of O(n^2), in terms of
  -- the number of nodes of the AST.
  -- We also try to reuse signal and ref variables for variables which are later
  -- on returned. We can reuse their signal and ref variables instead of introducing
  -- new ones. Note that, in case of a buffer, we still need to introduce an additional
  -- signal, which should be resolved when all operations on the buffer in the bound
  -- computation are resolved.
  --
  PartialDeclare
                :: SyncEnv genv
                -> GLeftHandSide bnd genv genv'
                -> TupR (Destination t) bnd
                -> Uniquenesses bnd
                -> PartialSchedule op genv  bnd
                -> PartialSchedule op genv' t
                -> PartialSchedule op genv  t

  PartialAcond  :: SyncEnv genv -- Stored for efficiency reasons to avoid recomputing it.
                -> ExpVar genv PrimBool
                -> PartialSchedule op genv t
                -> PartialSchedule op genv t
                -> PartialSchedule op genv t

  PartialAwhile :: SyncEnv genv
                -> Uniquenesses t
                -> PartialScheduleFun op genv (t -> PrimBool)
                -> PartialScheduleFun op genv (t -> t)
                -> GroundVars genv t
                -> PartialSchedule op genv t

partialDeclare  :: GLeftHandSide bnd genv genv'
                -> TupR (Destination t) bnd
                -> Uniquenesses bnd
                -> PartialSchedule op genv  bnd
                -> PartialSchedule op genv' t
                -> PartialSchedule op genv  t
partialDeclare lhs dest us bnd sched = PartialDeclare sync lhs dest us bnd sched
  where
    sync = unionPartialEnv max (syncEnv bnd) (weakenSyncEnv lhs $ syncEnv sched)

partialAcond    :: ExpVar genv PrimBool
                -> PartialSchedule op genv t
                -> PartialSchedule op genv t
                -> PartialSchedule op genv t
partialAcond cond t f = PartialAcond sync cond t f
  where
    sync = unionPartialEnv max (syncEnv t) (syncEnv f)

partialAwhile   :: Uniquenesses t
                -> PartialScheduleFun op genv (t -> PrimBool)
                -> PartialScheduleFun op genv (t -> t)
                -> GroundVars genv t
                -> PartialSchedule op genv t
partialAwhile us cond f vars = PartialAwhile sync us cond f vars
  where
    sync = unionPartialEnv max (syncEnvFun cond) $ unionPartialEnv max (syncEnvFun f) $ variablesToSyncEnv us vars

data PartialScheduleFun op genv t where
  Plam  :: GLeftHandSide s genv genv'
        -> PartialScheduleFun op genv' t
        -> PartialScheduleFun op genv (s -> t)

  Pbody :: PartialSchedule    op genv  t
        -> PartialScheduleFun op genv  t

instance HasGroundsR (PartialSchedule op genv) where
  groundsR (PartialDo doOutput _ _) = partialDoOutputGroundsR doOutput
  groundsR (PartialReturn _ vars) = mapTupR varType vars
  groundsR (PartialDeclare _ _ _ _ _ p) = groundsR p
  groundsR (PartialAcond _ _ p _) = groundsR p
  groundsR (PartialAwhile _ _ _ _ vars) = groundsR vars

data MaybeVar genv t where
  NoVars    :: MaybeVar genv t
  ReturnVar :: GroundVar genv t -> MaybeVar genv t
type MaybeVars genv = TupR (MaybeVar genv)

weakenMaybeVar :: LeftHandSide s t genv genv' -> MaybeVar genv' u -> MaybeVar genv u
weakenMaybeVar _ NoVars = NoVars
weakenMaybeVar (LeftHandSideWildcard _) v = v
weakenMaybeVar (LeftHandSideSingle _) (ReturnVar (Var t ix)) = case ix of
  SuccIdx ix' -> ReturnVar $ Var t ix'
  ZeroIdx     -> NoVars
weakenMaybeVar (LeftHandSidePair l1 l2) v = weakenMaybeVar l1 $ weakenMaybeVar l2 v

weakenMaybeVars :: LeftHandSide s t genv genv' -> MaybeVars genv' u -> MaybeVars genv u
weakenMaybeVars lhs = mapTupR (weakenMaybeVar lhs)

-- We can only reuse the resulting address of a variable if the local binding is not used elsewhere.
-- For instance, we may reuse the return address for x in `let x = .. in x`,
-- but that is not allowed in `let x = .. in let y = .. x .. in (x, y)`
-- or `let x = .. in (x, x)`.
-- This function removes a set of variables and can be used to remove for instance the set of variables
-- used in another binding or effect.
removeMaybeVars :: forall genv u. MaybeVars genv u -> IdxSet genv -> MaybeVars genv u
removeMaybeVars vars remove = mapTupR f vars
  where
    f :: MaybeVar genv t -> MaybeVar genv t
    f var@(ReturnVar (Var _ idx))
      | idx `IdxSet.member` remove = NoVars
      | otherwise         = var
    f NoVars = NoVars

lhsDestination :: GLeftHandSide t genv genv' -> MaybeVars genv' u -> TupR (Destination u) t
lhsDestination (LeftHandSidePair l1 l2) vars = lhsDestination l1 (weakenMaybeVars l2 vars) `TupRpair` lhsDestination l2 vars
lhsDestination (LeftHandSideWildcard t) _    = mapTupR (const DestinationNew) t
lhsDestination (LeftHandSideSingle _)   vars = case findVar vars of
    Just ix -> TupRsingle $ DestinationReuse ix
    Nothing -> TupRsingle DestinationNew
  where
    findVar :: MaybeVars (env, t) s -> Maybe (TupleIdx s t)
    findVar (TupRpair a b) = case (findVar a, findVar b) of
      (Just i , _     ) -> Just $ TupleIdxLeft i
      (Nothing, Just i) -> Just $ TupleIdxRight i
      _                 -> Nothing
    findVar (TupRsingle (ReturnVar (Var _ ZeroIdx))) = Just TupleIdxSelf
    findVar TupRunit = Nothing -- Should be unreachable

joinVars :: MaybeVars genv t -> MaybeVars genv t -> MaybeVars genv t
joinVars m@(TupRsingle (ReturnVar (Var _ x))) (TupRsingle (ReturnVar (Var _ y)))
  | x == y = m
joinVars (TupRpair x1 x2) (TupRpair y1 y2) = joinVars x1 y1 `TupRpair` joinVars x2 y2
joinVars TupRunit         _                = TupRunit
joinVars _                TupRunit         = TupRunit
joinVars _                _                = TupRsingle NoVars

data Exists' (a :: (Type -> Type -> Type) -> Type) where
  Exists' :: a m -> Exists' a

partialSchedule :: forall op genv1 t1. C.PartitionedAcc op genv1 t1 -> (PartialSchedule op genv1 t1, IdxSet genv1)
partialSchedule = (\(s, used, _) -> (s, used)) . travA (TupRsingle Shared)
  where
    travA :: forall genv t. Uniquenesses t -> C.PartitionedAcc op genv t -> (PartialSchedule op genv t, IdxSet genv, MaybeVars genv t)
    travA _  (C.Exec cluster)
      | Exists env <- convertEnvFromList $ map (foldr1 combineMod) $ groupBy (\(Exists v1) (Exists v2) -> isJust $ matchIdx (varIdx v1) (varIdx v2)) $ execVars cluster -- TODO: Remove duplicates more efficiently
      , Reads reEnv k inputBindings <- readRefs $ convertEnvRefs env
      , Just cluster' <- reindexExecPartial (reEnvIdx reEnv) cluster
        = let
            signals = convertEnvSignals env
            resolvers = convertEnvSignalResolvers k env
          in
            ( PartialDo PartialDoOutputUnit env
                $ Effect (SignalAwait signals)
                $ inputBindings
                $ Effect (Exec cluster')
                $ Effect (SignalResolve resolvers)
                $ Return
            , IdxSet.fromList $ convertEnvToList env
            , TupRunit
            )
      | otherwise = error "partialSchedule: reindexExecPartial returned Nothing. Probably some variable is missing in 'execVars'"
      where
        combineMod :: Exists (Var AccessGroundR env) -> Exists (Var AccessGroundR env) -> Exists (Var AccessGroundR env)
        combineMod (Exists (Var (AccessGroundRbuffer m1 tp) ix)) var@(Exists (Var (AccessGroundRbuffer m2 _) _))
          | Exists' m <- combineMod' m1 m2 = Exists $ Var (AccessGroundRbuffer m tp) ix
          | otherwise = var

        combineMod' :: Modifier m -> Modifier m' -> Exists' Modifier
        combineMod' In  In  = Exists' In
        combineMod' Out Out = Exists' Out
        combineMod' _   _   = Exists' Mut
    travA us (C.Return vars)  = (PartialReturn us vars, IdxSet.fromVarList $ flattenTupR vars, mapTupR f vars)
      where
        duplicates = map head $ filter (\g -> length g >= 2) $ group $ sort $ map (\(Exists (Var _ ix)) -> idxToInt ix) $ flattenTupR vars

        f :: GroundVar genv t' -> MaybeVar genv t'
        f v@(Var _ idx)
          | idxToInt idx `elem` duplicates = NoVars
          | otherwise = ReturnVar v
    travA _  (C.Compute e)    = partialLift (mapTupR GroundRscalar $ expType e) f (expGroundVars e)
      where
        f :: genv :?> fenv -> Maybe (Binding fenv t)
        f k = Compute <$> strengthenArrayInstr k e
    travA us (C.Alet lhs us' bnd a) = (partialDeclare lhs dest us' bnd' a', used1 `IdxSet.union` IdxSet.drop' lhs used2, vars')
      where
        dest = lhsDestination lhs vars
        (bnd', used1, _) = travA us' bnd
        (a', used2, vars) = travA us a
        vars' = weakenMaybeVars lhs vars `removeMaybeVars` used1
    travA _  (C.Alloc shr tp sh) = partialLift1 (TupRsingle $ GroundRbuffer tp) (Alloc shr tp) sh
    travA _  (C.Use tp buffer) = partialLift1 (TupRsingle $ GroundRbuffer tp) (const $ Use tp buffer) TupRunit
    travA _  (C.Unit var@(Var tp _)) = partialLift1 (TupRsingle $ GroundRbuffer tp) f (TupRsingle var)
      where
        f (TupRsingle var') = Unit var'
    travA us (C.Acond c t f) = (partialAcond c t' f', IdxSet.union used1 used2, vars)
      where
        (t', used1, vars1) = travA us t
        (f', used2, vars2) = travA us f
        vars = joinVars vars1 vars2
    travA _  (C.Awhile us c f vars) = (partialAwhile us c' f' vars, used1 `IdxSet.union` used2 `IdxSet.union` IdxSet.fromVarList (flattenTupR vars), TupRsingle NoVars)
      where
        (c', used1) = partialScheduleFun c
        (f', used2) = partialScheduleFun f

partialScheduleFun :: C.PartitionedAfun op genv t -> (PartialScheduleFun op genv t, IdxSet genv)
partialScheduleFun (C.Alam lhs f) = (Plam lhs f', IdxSet.drop' lhs used)
  where
    (f', used) = partialScheduleFun f
partialScheduleFun (C.Abody b)    = (Pbody b', used)
  where
    (b', used) = partialSchedule b

partialLift1 :: GroundsR s -> (forall fenv. ExpVars fenv t -> Binding fenv s) -> ExpVars genv t -> (PartialSchedule op genv s, IdxSet genv, MaybeVars genv s)
partialLift1 tp f vars = partialLift tp (\k -> f <$> strengthenVars k vars) (expVarsList vars)

expVarsList :: ExpVars genv t -> [Exists (GroundVar genv)]
expVarsList = (`go` [])
  where
    go :: ExpVars genv t -> [Exists (GroundVar genv)] -> [Exists (GroundVar genv)]
    go TupRunit                 accum = accum
    go (TupRsingle (Var tp ix)) accum = Exists (Var (GroundRscalar tp) ix) : accum
    go (TupRpair v1 v2)         accum = go v1 $ go v2 accum

strengthenVars :: genv :?> fenv -> Vars s genv t -> Maybe (Vars s fenv t)
strengthenVars k TupRunit                = pure TupRunit
strengthenVars k (TupRsingle (Var t ix)) = TupRsingle . Var t <$> k ix
strengthenVars k (TupRpair v1 v2)        = TupRpair <$> strengthenVars k v1 <*> strengthenVars k v2

partialLift :: forall op genv s. GroundsR s -> (forall fenv. genv :?> fenv -> Maybe (Binding fenv s)) -> [Exists (GroundVar genv)] -> (PartialSchedule op genv s, IdxSet genv, MaybeVars genv s)
partialLift tp f vars
  | DefineOutput doOutput kOut varsOut <- defineOutput @() @s tp (mapTupR uniqueIfBuffer tp)
  , Exists env <- convertEnvReadonlyFromList $ nubBy (\(Exists v1) (Exists v2) -> isJust $ matchVar v1 v2) vars -- TODO: Remove duplicates more efficiently
  , Reads reEnv k inputBindings <- readRefs $ convertEnvRefs env
  , DeclareVars lhs k' value <- declareVars $ mapTupR BaseRground tp
  , Just binding <- f (reEnvIdx reEnv)
  =
    let
      signals = convertEnvSignals env
      resolvers = convertEnvSignalResolvers (k' .> k) env
    in
      ( PartialDo doOutput env
          $ Effect (SignalAwait signals)
          $ inputBindings
          $ Alet lhs binding
          $ Effect (SignalResolve resolvers)
          $ writeOutput doOutput (varsOut (k' .> k .> convertEnvWeaken env)) (value weakenId)
      , IdxSet.fromList $ convertEnvToList env
      , mapTupR (const NoVars) tp
      )

uniqueIfBuffer :: GroundR t -> Uniqueness t
uniqueIfBuffer (GroundRbuffer _) = Unique
uniqueIfBuffer _                 = Shared

syncEnv :: PartialSchedule op genv t -> SyncEnv genv
syncEnv (PartialDo _ env _)          = convertEnvToSyncEnv env
syncEnv (PartialReturn u vars)       = variablesToSyncEnv u vars
syncEnv (PartialDeclare s _ _ _ _ _) = s
syncEnv (PartialAcond s _ _ _)       = s
syncEnv (PartialAwhile s _ _ _ _)    = s

syncEnvFun :: PartialScheduleFun op genv t -> SyncEnv genv
syncEnvFun (Plam lhs f) = weakenSyncEnv lhs $ syncEnvFun f
syncEnvFun (Pbody s)    = syncEnv s

convertEnvToSyncEnv :: ConvertEnv genv fenv fenv' -> SyncEnv genv
convertEnvToSyncEnv = partialEnvFromList (error "convertEnvToSyncEnv: Variable occurs multiple times") . (`go` [])
  where
    go :: ConvertEnv genv fenv fenv' -> [EnvBinding Sync genv] -> [EnvBinding Sync genv]
    go (ConvertEnvSeq env1 env2)                  accum = go env1 $ go env2 accum
    go (ConvertEnvAcquire (Acquire m (Var _ ix))) accum = EnvBinding ix s : accum
      where
        s = case m of
          In -> SyncRead
          _  -> SyncWrite
    go _ accum = accum

variablesToSyncEnv :: Uniquenesses t -> GroundVars genv t -> SyncEnv genv
variablesToSyncEnv uniquenesses vars = partialEnvFromList (error "convertEnvToSyncEnv: Variable occurs multiple times") $ go uniquenesses vars []
  where
    go :: Uniquenesses t -> GroundVars genv t -> [EnvBinding Sync genv] -> [EnvBinding Sync genv]
    go (TupRsingle Unique) (TupRsingle (Var (GroundRbuffer _) ix))
                          accum = EnvBinding ix SyncWrite : accum
    go (TupRsingle Shared) (TupRsingle (Var (GroundRbuffer _) ix))
                          accum = EnvBinding ix SyncRead : accum
    go u (TupRpair v1 v2) accum = go u1 v1 $ go u2 v2 accum
      where (u1, u2) = pairUniqueness u
    go _ _                accum = accum

pairUniqueness :: Uniquenesses (s, t) -> (Uniquenesses s, Uniquenesses t)
pairUniqueness (TupRpair u1 u2)    = (u1, u2)
pairUniqueness (TupRsingle Shared) = (TupRsingle Shared, TupRsingle Shared)

{-
-- Combines two sync values from two subterms, where the first subterm uses
-- the buffers first. At this location we must introduce new signals to
-- synchronize that.
-- Returns:
--   * Number of signals to grant write access (ie one per read operation,
--     indicating that the read has finished and the data can be overriden.)
--   * Number of signals to grant read access (ie one per write operation)
--     Note that one has to wait on both the read access signals and the
--     write access signals to get write access.
--   * A merged Sync value
--
combineSync :: Sync t -> Sync t -> (Int, Int, Sync t)
combineSync (SyncRead  r)   (SyncRead  r')    = (0, 0, SyncRead (r + r'))
combineSync (SyncRead  r)   (SyncWrite r' w') = (r, 0, SyncWrite r' w')
combineSync (SyncWrite r w) (SyncWrite r' w') = (r, w, SyncWrite r' w')
combineSync (SyncWrite r w) (SyncRead  r')    = (0, 0, SyncWrite (r + r') w)

combineSync' :: Sync t -> Sync t -> Sync t
combineSync' a b = c
  where (_, _, c) = combineSync a b
-}
weakenSyncEnv :: GLeftHandSide t env env' -> SyncEnv env' -> SyncEnv env
weakenSyncEnv _                        PEnd          = PEnd
weakenSyncEnv (LeftHandSideWildcard _) env           = env
weakenSyncEnv (LeftHandSideSingle _)   (PPush env _) = env
weakenSyncEnv (LeftHandSideSingle _)   (PNone env)   = env
weakenSyncEnv (LeftHandSidePair l1 l2) env           = weakenSyncEnv l1 $ weakenSyncEnv l2 env
{-
maxSync :: Sync t -> Sync t -> Sync t
maxSync (SyncRead r)    (SyncRead r')     = SyncRead (max r r')
maxSync (SyncRead r)    (SyncWrite w' r') = SyncWrite w' (max r r')
maxSync (SyncWrite w r) (SyncRead r')     = SyncWrite w (max r r')
maxSync (SyncWrite w r) (SyncWrite w' r') = SyncWrite (max w w') (max r r') 
-}

-- TODO: Better name
data Lock fenv
  = Borrow (Idx fenv Signal) (Idx fenv SignalResolver)
  | Move (Idx fenv Signal)

lockSignal :: Lock fenv -> Idx fenv Signal
lockSignal (Borrow s _) = s
lockSignal (Move s) = s

setLockSignal :: Idx fenv Signal -> Lock fenv -> Lock fenv
setLockSignal s (Borrow _ r) = Borrow s r
setLockSignal s (Move _)     = Move s

data Future fenv t where
  FutureScalar :: ScalarType t
               -> Idx fenv Signal
               -> Idx fenv (Ref t)
               -> Future fenv t

  -- A buffer has a signal to denote that the Ref may be read,
  -- and signals and resolvers grouped in Locks to synchronize
  -- read and write access to the buffer.
  -- Informal properties / invariants:
  --  - If the read signal is resolved, then we may read from
  --    the array.
  --  - If the signals of the read and write access are both
  --    resolved, then we may destructively update the array.
  --  - The read resolver may only be resolved after the read
  --    signal is resolved.
  --  - The write resolver may only be resolved after both
  --    the read and write signals are resolved.
  FutureBuffer :: ScalarType t
               -> Idx fenv Signal -- This signal is resolved when the Ref is filled.
               -> Idx fenv (Ref (Buffer t))
               -> Lock fenv -- Read access
               -> Maybe (Lock fenv) -- Write access, if needed
               -> Future fenv (Buffer t)

type FutureEnv fenv = PartialEnv (Future fenv)

instance Sink' Lock where
  weaken' k (Borrow s r) = Borrow (weaken k s) (weaken k r)
  weaken' k (Move s)     = Move (weaken k s)

instance Sink Future where
  weaken k (FutureScalar tp signal ref) = FutureScalar tp (weaken k signal) (weaken k ref)
  weaken k (FutureBuffer tp signal ref read write)
    = FutureBuffer
        tp
        (weaken k signal)
        (weaken k ref)
        (weaken' k read)
        (weaken' k <$> write)

-- Implementation of the sub-environment rule, by restricting the futures
-- in the FutureEnv to the abilities required by the SyncEnv.
-- Creates a sub-environment, providing only the futures needed in some subterm.
-- Also returns a list of locks which are not used in this sub-environment
-- (because the buffer is not used in that sub-term, or the sub-term doesn't require
-- write access for that buffer). Those locks should be resolved, ie, we should fork
-- a thread, wait on the signal and resolve the resolver, such that later operations
-- can get access to the resource.
--
subFutureEnvironment :: forall fenv genv op. FutureEnv fenv genv -> SyncEnv genv -> (FutureEnv fenv genv, [UniformSchedule (Cluster op) fenv])
subFutureEnvironment (PNone fenv) (PNone senv) = (PNone fenv', actions)
  where
    (fenv', actions) = subFutureEnvironment fenv senv
subFutureEnvironment (PPush fenv f@(FutureScalar _ _ _)) senv = (PPush fenv' f, actions)
  where
    (fenv', actions) = subFutureEnvironment fenv $ partialEnvTail senv
subFutureEnvironment (PPush fenv f@(FutureBuffer tp signal ref read write)) (PPush senv sync) = (PPush fenv' f', action ++ actions)
  where
    (fenv', actions) = subFutureEnvironment fenv senv

    (f', action)
      | Nothing <- write,             SyncRead  <- sync -- No need to change
        = (f, [])
      | Just _ <- write,              SyncWrite <- sync -- No need to change
        = (f, [])
      | Nothing <- write,             SyncWrite <- sync -- Illegal input
        = internalError "Got a FutureBuffer without write capabilities, but the SyncEnv asks for write permissions"
      | Just (Borrow ws wr) <- write, SyncRead  <- sync -- Write capability not used
        = ( FutureBuffer tp signal ref read write
          -- Resolve the write resolver after taking both the read and write signal
          , [Effect (SignalAwait [lockSignal read, ws]) $ Effect (SignalResolve [wr]) Return]
          )
      | Just (Move _) <- write,       SyncRead  <- sync
        = ( FutureBuffer tp signal ref read Nothing
          , []
          )
subFutureEnvironment (PPush fenv (FutureBuffer tp signal ref read write)) (PNone senv) = (PNone fenv', action ++ actions)
  where
    (fenv', actions) = subFutureEnvironment fenv senv

    action
      | Borrow rs rr <- read
      , Just (Borrow ws wr) <- write
        = return
        $ Effect (SignalResolve [rr])
        $ Effect (SignalAwait [rs, ws])
        $ Effect (SignalResolve [wr]) Return
      | Move rs <- read
      , Just (Borrow ws wr) <- write
        = return
        $ Effect (SignalAwait [rs, ws])
        $ Effect (SignalResolve [wr]) Return
      | Borrow _ rr <- read
        = return
        $ Effect (SignalResolve [rr]) Return
      | otherwise = []
subFutureEnvironment PEnd _ = (PEnd, [])
subFutureEnvironment _ _ = internalError "Keys of SyncEnv are not a subset of the keys of the FutureEnv"

sub :: forall fenv genv op. FutureEnv fenv genv -> SyncEnv genv -> (FutureEnv fenv genv -> UniformSchedule (Cluster op) fenv) -> UniformSchedule (Cluster op) fenv
sub fenv senv body = forks (body fenv' : actions)
  where
    (fenv', actions) = subFutureEnvironment fenv senv

-- Data type for the existentially qualified type variable fenv' used in chainFuture
data ChainFutureEnv op fenv genv where
  ChainFutureEnv :: (UniformSchedule (Cluster op) fenv' -> UniformSchedule (Cluster op) fenv) -> fenv :> fenv' -> FutureEnv fenv' genv -> FutureEnv fenv' genv -> ChainFutureEnv op fenv genv

chainFutureEnvironment :: fenv :> fenv' -> FutureEnv fenv genv -> SyncEnv genv -> SyncEnv genv -> ChainFutureEnv op fenv' genv
chainFutureEnvironment _ PEnd PEnd PEnd = ChainFutureEnv id weakenId PEnd PEnd
-- Used in both subterms
chainFutureEnvironment k (PPush fenv f) (PPush senvLeft sLeft) (PPush senvRight sRight)
  | ChainFuture    instr1 k1 fLeft    fRight    <- chainFuture (weaken k f) sLeft sRight
  , ChainFutureEnv instr2 k2 fenvLeft fenvRight <- chainFutureEnvironment (k1 .> k) fenv senvLeft senvRight
  = ChainFutureEnv
      (instr1 . instr2)
      (k2 .> k1)
      (PPush fenvLeft  $ weaken k2 fLeft)
      (PPush fenvRight $ weaken k2 fRight)
-- Only used in left subterm
chainFutureEnvironment k (PPush fenv f) (PPush senvLeft _) senvRight
  | ChainFutureEnv instr k1 fenvLeft fenvRight <- chainFutureEnvironment k fenv senvLeft (partialEnvTail senvRight)
  = ChainFutureEnv instr k1 (PPush fenvLeft (weaken (k1 .> k) f)) (partialEnvSkip fenvRight)
-- Only used in right subterm
chainFutureEnvironment k (PPush fenv f) senvLeft (PPush senvRight _)
  | ChainFutureEnv instr k1 fenvLeft fenvRight <- chainFutureEnvironment k fenv (partialEnvTail senvLeft) senvRight
  = ChainFutureEnv instr k1 (partialEnvSkip fenvLeft) (PPush fenvRight (weaken (k1 .> k) f))
-- Index not present
chainFutureEnvironment k (PNone fenv) senvLeft senvRight
  | ChainFutureEnv instr k1 fenvLeft fenvRight <- chainFutureEnvironment k fenv (partialEnvTail senvLeft) (partialEnvTail senvRight)
  = ChainFutureEnv instr k1 (partialEnvSkip fenvLeft) (partialEnvSkip fenvRight)
chainFutureEnvironment _ _ _ _ = internalError "Illegal case. The keys of the FutureEnv should be the union of the keys of the two SyncEnvs."

-- Data type for the existentially qualified type variable fenv' used in chainFuture
data ChainFuture op fenv t where
  ChainFuture :: (UniformSchedule (Cluster op) fenv' -> UniformSchedule (Cluster op) fenv) -> fenv :> fenv' -> Future fenv' t -> Future fenv' t -> ChainFuture op fenv t

chainFuture :: Future fenv t -> Sync t -> Sync t -> ChainFuture op fenv t
chainFuture (FutureScalar tp _ _) SyncRead  _ = bufferImpossible tp
chainFuture (FutureScalar tp _ _) SyncWrite _ = bufferImpossible tp

-- Read before read, without a release
--          Left     Right
-- Read  --> X      -> X
--        \       /
--          -----
chainFuture f@(FutureBuffer _ _ _ (Move _) mwrite) SyncRead SyncRead
  | Just _ <- mwrite = internalError "Expected a FutureBuffer without write lock"
  | Nothing <- mwrite
  = ChainFuture
      -- This doesn't require any additional signals
      id
      weakenId
      f
      f

-- Read before read
--          Left     Right
--               -------
--             /         \
-- Read  --> X      -> X -->
--        \       /
--          -----
chainFuture (FutureBuffer tp signal ref (Borrow s r) mwrite) SyncRead SyncRead
  | Just _ <- mwrite = internalError "Expected a FutureBuffer without write lock"
  | Nothing <- mwrite
  = ChainFuture 
      -- Create a pair of signal and resolver for both subterms.
      -- Fork a thread which will resolve the final read signal when the two
      -- new signals have been resolved.
      ( Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Fork (Effect (SignalAwait [signal1, signal2]) $ Effect (SignalResolve [weaken k r]) Return)
      )
      -- Weaken all other identifiers with four, as we introduced two new signals
      -- and two new signal resolvers.
      k
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow (weaken k s) resolver1)
          Nothing
      )
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow (weaken k s) resolver2)
          Nothing
      )
  where
    k = weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId

    signal1   = SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    resolver1 = SuccIdx $ SuccIdx $ ZeroIdx
    signal2   = SuccIdx $ ZeroIdx
    resolver2 = ZeroIdx

-- Write before read, without release
--          Left     Right
-- Read  --> X       > X
--                 /
--               /
--             /
-- Write --> X
--
-- Note that the left subterm must synchronise its read and write operations itself.
chainFuture (FutureBuffer tp signal ref (Move readSignal) (Just (Move writeSignal))) SyncWrite SyncRead
  = ChainFuture
      -- Create a signal to let the read operation in the second subterm only
      -- start after the write operation of the first subterm has finished.
      ( Alet lhsSignal NewSignal )
      k
      -- The first subterm must resolve the new signal after finishing its write operation.
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Move $ weaken k readSignal)
          (Just $ Borrow (weaken k $ writeSignal) writeResolver)
      )
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Move writeSignal2)
          Nothing
      )
  where
    k = weakenSucc $ weakenSucc weakenId
    writeSignal2  = SuccIdx $ ZeroIdx
    writeResolver = ZeroIdx

-- Write before read
--          Left     Right
--               -------
--             /         \
-- Read  --> X       > X -->
--                 /
--               /
--             /
-- Write --> X ------------->
-- Note that the left subterm must synchronise its read and write operations itself.
chainFuture (FutureBuffer tp signal ref (Borrow readSignal readRelease) (Just (Borrow writeSignal writeRelease))) SyncWrite SyncRead
  = ChainFuture
      -- Create a signal (signal1) to let the read operation in the second subterm only
      -- start after the write operation of the first subterm has finished.
      -- Also create signals (signal2 and signal3) to denote that the read operations
      -- of respectively the left and right subterm have finished.
      -- 'readRelease' will be resolved when signal2 and signal3 are both resolved.
      -- 'writeRelease' will be resolved when signal1 is resolved.
      ( Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Fork (Effect (SignalAwait [signal2, signal3]) $ Effect (SignalResolve [weaken k readRelease]) Return)
        . Fork (Effect (SignalAwait [signal1]) $ Effect (SignalResolve [weaken k writeRelease]) Return)
      )
      k
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow (weaken k readSignal) resolver2)
          (Just $ Borrow (weaken k writeSignal) resolver1)
      )
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow signal1 resolver3)
          Nothing
      )
  where
    k = weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId

    signal1   = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    resolver1 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ ZeroIdx
    signal2   = SuccIdx $ SuccIdx $ SuccIdx $ ZeroIdx
    resolver2 = SuccIdx $ SuccIdx $ ZeroIdx
    signal3   = SuccIdx $ ZeroIdx
    resolver3 = ZeroIdx

-- Write before read, with a write release
--          Left     Right
-- Read  --> X       > X
--                 /
--               /
--             /
-- Write --> X ------------->
-- Note that the left subterm must synchronise its read and write operations itself.
chainFuture (FutureBuffer tp signal ref (Move readSignal) (Just (Borrow writeSignal writeRelease))) SyncWrite SyncRead
  = ChainFuture
      -- Create a signal to let the read operation in the second subterm only
      -- start after the write operation of the first subterm has finished.
      -- 'writeSignal' can be resolved when this newly introduced signal
      -- is resolved.
      ( Alet lhsSignal NewSignal
        . Fork (Effect (SignalAwait [signal1]) $ Effect (SignalResolve [weaken k writeRelease]) Return)
      )
      -- Weaken all other identifiers with two, as we introduced a new signal
      -- and a new signal resolver
      k
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Move (weaken k readSignal))
          (Just $ Borrow (weaken k writeSignal) resolver1)
      )
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Move signal1)
          Nothing
      )
  where
    k = weakenSucc $ weakenSucc weakenId
    signal1   = SuccIdx $ ZeroIdx
    resolver1 = ZeroIdx

-- Invalid cases of write-before-read
chainFuture (FutureBuffer _ _ _ _ Nothing) SyncWrite SyncRead = internalError "Expected a FutureBuffer with write lock"
chainFuture (FutureBuffer _ _ _ (Borrow _ _) (Just (Move _))) SyncWrite SyncRead = internalError "Illegal FutureBuffer with Borrow-Move locks"

-- Read before write
--          Left     Right
--          -----
--        /       \
-- Read  --> X      -> X -->
--             \
--               \
--                 \
-- Write ------------> X -->
chainFuture (FutureBuffer tp signal ref read mwrite) SyncRead SyncWrite
  | Nothing <- mwrite = internalError "Expected a FutureBuffer with write lock"
  | Just write <- mwrite
  = ChainFuture
      -- Create a signal to let the write operation in the second subterm only
      -- start after the read operation of the first subterm has finished.
      -- Also create a signal which will be resolved when the newly introduced signal
      -- and the incoming write signal are both resolved.
      ( Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Fork (Effect (SignalAwait [weaken k $ lockSignal write, signal1]) $ Effect (SignalResolve [resolver2]) Return)
      )
      -- Weaken all other identifiers with four, as we introduced two new signals
      -- and two new signal resolvers.
      k
      -- The first subterm must resolve the new signal after finishing its read operation.
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow (weaken k $ lockSignal read) resolver1)
          Nothing
      )
      -- The second subterm must wait on the signal before it can start the write operation.
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (weaken' k read)
          (Just $ setLockSignal signal2 $ weaken' k write)          
      )
  where
    k = weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId

    signal1   = SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    resolver1 = SuccIdx $ SuccIdx $ ZeroIdx
    signal2   = SuccIdx $ ZeroIdx
    resolver2 = ZeroIdx

-- Write before write
--          Left     Right
-- Read  --> X       > X -->
--             \   /
--               X
--             /   \
-- Write --> X ------> X -->
chainFuture (FutureBuffer tp signal ref read mwrite) SyncWrite SyncWrite
  | Nothing <- mwrite = internalError "Expected a FutureBuffer with write lock"
  | Just write <- mwrite
  = ChainFuture
      -- Create two signals (signal1 and signal2) to let the first subterm
      -- inform that respectively its read or write operations have finished.
      -- Also create a signal (signal3) which is resolved when signal1 and
      -- signal2 are both resolved.
      ( Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Alet lhsSignal NewSignal
        . Fork (Effect (SignalAwait [signal1, signal2]) $ Effect (SignalResolve [resolver3]) Return)
      )
      k
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (Borrow (weaken k $ lockSignal read) resolver1)
          (Just $ Borrow (weaken k $ lockSignal write) resolver2)
      )
      ( FutureBuffer
          tp
          (weaken k signal)
          (weaken k ref)
          (setLockSignal signal2 $ weaken' k read)
          (Just $ setLockSignal signal3 $ weaken' k write)
      )
  where
    k = weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId

    signal1   = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    resolver1 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ ZeroIdx
    signal2   = SuccIdx $ SuccIdx $ SuccIdx $ ZeroIdx
    resolver2 = SuccIdx $ SuccIdx $ ZeroIdx
    signal3   = SuccIdx $ ZeroIdx
    resolver3 = ZeroIdx

lhsSignal :: LeftHandSide BaseR (Signal, SignalResolver) fenv ((fenv, Signal), SignalResolver)
lhsSignal = LeftHandSidePair (LeftHandSideSingle BaseRsignal) (LeftHandSideSingle BaseRsignalResolver)

lhsRef :: GroundR tp -> LeftHandSide BaseR (Ref tp, OutputRef tp) fenv ((fenv, Ref tp), OutputRef tp)
lhsRef tp = LeftHandSidePair (LeftHandSideSingle $ BaseRref tp) (LeftHandSideSingle $ BaseRrefWrite tp)

-- Similar to 'fromPartial', but also applies the sub-environment rule 
fromPartialSub
  :: forall op fenv genv t r.
     HasCallStack
  => OutputEnv t r
  -> BaseVars fenv r
  -> FutureEnv fenv genv
  -> PartialSchedule op genv t
  -> UniformSchedule (Cluster op) fenv
fromPartialSub outputEnv outputVars env partial
  = sub env (syncEnv partial) (\env' -> fromPartial outputEnv outputVars env' partial)

fromPartialFun
  :: forall op fenv genv t r.
     HasCallStack
  => FutureEnv fenv genv
  -> PartialScheduleFun op genv t
  -> UniformScheduleFun (Cluster op) fenv (ScheduleFunction t)
fromPartialFun env = \case
  Pbody body
    | grounds <- groundsR body
    , Refl <- scheduleFunctionIsBody $ grounds
    , DeclareOutput k1 lhs k2 instr outputEnv outputVars <- declareOutput grounds
    -> Slam lhs $ Sbody $ instr $ fromPartial outputEnv (outputVars weakenId) (mapPartialEnv (weaken (k2 .> k1)) env) body
  Plam lhs fun
    | DeclareInput _ lhs' env' <- declareInput env lhs
    -> Slam lhs' $ fromPartialFun (env' weakenId) fun

fromPartial
  :: forall op fenv genv t r.
     HasCallStack
  => OutputEnv t r
  -> BaseVars fenv r
  -> FutureEnv fenv genv
  -> PartialSchedule op genv t
  -> UniformSchedule (Cluster op) fenv
fromPartial outputEnv outputVars env = \case
    PartialDo outputEnv' convertEnv (schedule :: UniformSchedule (Cluster op) fenv')
      | Just Refl <- matchOutputEnvWithEnv outputEnv outputEnv' ->
        let
          kEnv = partialDoSubstituteOutput outputEnv' outputVars
          kEnv' :: Env (NewIdx fenv) fenv'
          kEnv' = partialDoSubstituteConvertEnv convertEnv env kEnv

          k :: ReindexPartialN Identity fenv' fenv
          k idx = Identity $ prj' idx kEnv'
        in
          runIdentity $ reindexSchedule k schedule -- Something with a substitution
      | otherwise -> internalError "OutputEnv and PartialDoOutput do not match"
    PartialReturn uniquenesses vars -> travReturn vars 
    PartialDeclare syncEnv lhs dest uniquenesses bnd body
      | DeclareBinding k instr outputEnvBnd outputVarsBnd env' <- declareBinding outputEnv outputVars env lhs dest uniquenesses ->
        instr $ Fork
          (fromPartial outputEnvBnd (outputVarsBnd weakenId) (mapPartialEnv (weaken k) env) bnd)
          (fromPartial outputEnv (mapTupR (weaken k) outputVars) (env' weakenId) body)
    PartialAcond _ condition true false -> acond condition true false
    PartialAwhile _ uniquenesses condition step initial -> awhile uniquenesses condition step initial
  where
    travReturn :: GroundVars genv t -> UniformSchedule (Cluster op) fenv
    travReturn vars = forks ((\(signals, s) -> await signals s) <$> travReturn' outputEnv outputVars vars [])

    travReturn' :: OutputEnv t' r' -> BaseVars fenv r' -> GroundVars genv t' -> [([Idx fenv Signal], UniformSchedule (Cluster op) fenv)] -> [([Idx fenv Signal], UniformSchedule (Cluster op) fenv)]
    travReturn' (OutputEnvPair o1 o2) (TupRpair r1 r2) (TupRpair v1 v2) accum = travReturn' o1 r1 v1 $ travReturn' o2 r2 v2 accum
    travReturn' (OutputEnvScalar tp') (TupRpair (TupRsingle destSignal) (TupRsingle destRef)) (TupRsingle (Var tp ix)) accum = task : accum
      where
        task = case prjPartial ix env of
          Nothing -> internalError "Variable not present in environment"
          Just (FutureScalar _ signal ref) ->
            ( [signal]
            , Alet (LeftHandSideSingle $ BaseRground tp) (RefRead $ Var (BaseRref tp) ref)
              $ Effect (RefWrite (weaken (weakenSucc weakenId) destRef) (Var (BaseRground tp) ZeroIdx))
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignal])
              $ Return
            )
          Just FutureBuffer{} -> bufferImpossible tp'
    travReturn' OutputEnvShared (TupRpair (TupRsingle destSignalRef `TupRpair` TupRsingle destSignalRead) (TupRsingle destRef)) (TupRsingle (Var tp ix)) accum = task : accum
      where
        task = case prjPartial ix env of
          Nothing -> internalError "Variable not present in environment"
          Just (FutureScalar tp' _ _) -> bufferImpossible tp'
          Just (FutureBuffer _ signal ref readAccess _) ->
            ( [signal]
            , Alet (LeftHandSideSingle $ BaseRground tp) (RefRead $ Var (BaseRref tp) ref)
              $ Effect (RefWrite (weaken (weakenSucc weakenId) destRef) (Var (BaseRground tp) ZeroIdx))
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignalRef])
              $ Effect (SignalAwait [weakenSucc weakenId >:> lockSignal readAccess])
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignalRead])
              $ Return
            )
    travReturn' OutputEnvUnique (TupRpair (TupRpair (TupRsingle destSignalRef `TupRpair` TupRsingle destSignalRead) (TupRsingle destSignalWrite)) (TupRsingle destRef)) (TupRsingle (Var tp ix)) accum = task : accum
      where
        task = case prjPartial ix env of
          Nothing -> internalError "Variale not present in environment"
          Just (FutureScalar tp' _ _) -> bufferImpossible tp'
          Just (FutureBuffer _ _ _ _ Nothing) -> internalError "Expected FutureBuffer with write access"
          Just (FutureBuffer _ signal ref readAccess (Just writeAccess)) ->
            ( [signal]
            , Alet (LeftHandSideSingle $ BaseRground tp) (RefRead $ Var (BaseRref tp) ref)
              $ Effect (RefWrite (weaken (weakenSucc weakenId) destRef) (Var (BaseRground tp) ZeroIdx))
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignalRef])
              $ Effect (SignalAwait [weakenSucc weakenId >:> lockSignal readAccess])
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignalRead])
              $ Effect (SignalAwait [weakenSucc weakenId >:> lockSignal writeAccess])
              $ Effect (SignalResolve [weakenSucc weakenId >:> varIdx destSignalWrite])
              $ Return
            )
    -- Destination was reused. No need to copy
    travReturn' OutputEnvIgnore _ _ accum = accum
    travReturn' _ _ _ _ = internalError "Invalid variables"

    acond :: ExpVar genv PrimBool -> PartialSchedule op genv t -> PartialSchedule op genv t -> UniformSchedule (Cluster op) fenv
    acond (Var _ condition) true false = case prjPartial condition env of
      Just (FutureScalar _ signal ref) ->
        -- Wait on the signal 
        Effect (SignalAwait [signal])
          -- Read the value of the condition
          $ Alet (LeftHandSideSingle $ BaseRground $ GroundRscalar scalarType) (RefRead $ Var (BaseRref $ GroundRscalar scalarType) ref)
          $ Acond
            (Var scalarType ZeroIdx)
            (fromPartialSub outputEnv outputVars' env' true)
            (fromPartialSub outputEnv outputVars' env' false)
            Return
      Nothing -> internalError "Variable not found"
      where
        outputVars' = mapTupR (weaken (weakenSucc weakenId)) outputVars
        env' = mapPartialEnv (weaken (weakenSucc weakenId)) env

    awhile
      :: Uniquenesses t
      -> PartialScheduleFun op genv (t -> PrimBool)
      -> PartialScheduleFun op genv (t -> t)
      -> GroundVars genv t
      -> UniformSchedule (Cluster op) fenv
    awhile = fromPartialAwhile outputEnv outputVars env

fromPartialAwhile
  :: forall op fenv genv t r.
     HasCallStack
  => OutputEnv t r
  -> BaseVars fenv r
  -> FutureEnv fenv genv
  -> Uniquenesses t
  -> PartialScheduleFun op genv (t -> PrimBool)
  -> PartialScheduleFun op genv (t -> t)
  -> GroundVars genv t
  -> UniformSchedule (Cluster op) fenv
fromPartialAwhile outputEnv outputVars env uniquenesses (Plam lhsC (Pbody condition)) (Plam lhsS (Pbody step)) initial
  | tp <- mapTupR varType initial
  , AwhileInputOutput io k lhsInput env' initial' outputEnv' <- awhileInputOutput env (\k -> mapPartialEnv (weaken k) env) uniquenesses initial
  = let
      

    in Awhile io undefined initial' Return

awhileInputOutput :: FutureEnv fenv0 genv0 -> (forall fenv''. fenv :> fenv'' -> FutureEnv fenv'' genv) -> Uniquenesses t -> GroundVars genv0 t -> AwhileInputOutput fenv0 fenv genv t
awhileInputOutput env0 env (TupRpair u1 u2) (TupRpair v1 v2)
  | AwhileInputOutput io1 k1 lhs1 env1 i1 outputEnv1 <- awhileInputOutput env0 env u1 v1
  , AwhileInputOutput io2 k2 lhs2 env2 i2 outputEnv2 <- awhileInputOutput env0 env1 u2 v2
  = AwhileInputOutput
      (InputOutputRpair io1 io2)
      (k2 .> k1)
      (LeftHandSidePair lhs1 lhs2)
      env2
      (TupRpair i1 i2)
      (OutputEnvPair outputEnv1 outputEnv2)
awhileInputOutput env0 env TupRunit TupRunit
  = AwhileInputOutput
      InputOutputRunit
      weakenId
      (LeftHandSideWildcard TupRunit)
      env
      TupRunit
      OutputEnvIgnore
awhileInputOutput env0 env (TupRsingle uniqueness) (TupRsingle (Var groundR idx))
  | GroundRbuffer tp <- groundR -- Unique buffer
  , Unique <- uniqueness
  = let
      initial = case prjPartial idx env0 of
        Just (FutureBuffer tp signal ref (Move signalRead) (Just (Move signalWrite))) ->
          TupRsingle (Var BaseRsignal signal)
          `TupRpair`
          TupRsingle (Var BaseRsignal signalRead)
          `TupRpair`
          TupRsingle (Var BaseRsignal signalWrite)
          `TupRpair`
          TupRsingle (Var (BaseRref $ GroundRbuffer tp) ref)
        Just (FutureBuffer _ _ _ _ Nothing) -> internalError "Expected a Future with write permissions."
        Just (FutureBuffer _ _ _ _ _) -> internalError "Expected Move. Cannot Borrow a variable into a loop."
        Just _ -> internalError "Illegal variable"
        Nothing -> internalError "Variable not found"
    in
      AwhileInputOutput
        (InputOutputRpair (InputOutputRpair (InputOutputRpair InputOutputRsignal InputOutputRsignal) InputOutputRsignal) InputOutputRref)
        -- Input
        (weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId)
        (LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle (BaseRref groundR))
        (\k -> env (weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc k) `PPush`
                FutureBuffer tp (k >:> SuccIdx (SuccIdx $ SuccIdx $ ZeroIdx)) (k >:> ZeroIdx) (Move (k >:> SuccIdx (SuccIdx ZeroIdx))) (Just $ Move (k >:> SuccIdx ZeroIdx)))
        initial
        -- Output
        OutputEnvUnique
  | GroundRbuffer tp <- groundR -- Shared buffer
  = let
      initial = case prjPartial idx env0 of
        Just (FutureBuffer tp signal ref (Move signalRead) _) ->
          TupRsingle (Var BaseRsignal signal)
          `TupRpair`
          TupRsingle (Var BaseRsignal signalRead)
          `TupRpair`
          TupRsingle (Var (BaseRref $ GroundRbuffer tp) ref)
        Just (FutureBuffer _ _ _ (Borrow _ _) _) -> internalError "Expected Move. Cannot Borrow a variable into a loop."
        Just _ -> internalError "Illegal variable"
        Nothing -> internalError "Variable not found"
    in
      AwhileInputOutput
        (InputOutputRpair (InputOutputRpair InputOutputRsignal InputOutputRsignal) InputOutputRref)
        -- Input
        (weakenSucc $ weakenSucc $ weakenSucc weakenId)
        (LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle (BaseRref groundR))
        (\k -> env (weakenSucc $ weakenSucc $ weakenSucc k) `PPush`
                FutureBuffer tp (k >:> SuccIdx (SuccIdx ZeroIdx)) (k >:> ZeroIdx) (Move (k >:> SuccIdx ZeroIdx)) Nothing)
        initial
        -- Output
        OutputEnvShared
  | GroundRscalar tp <- groundR -- Scalar
  = let
      initial = case prjPartial idx env0 of
        Just (FutureScalar tp signal ref) ->
          TupRsingle (Var BaseRsignal signal)
          `TupRpair`
          TupRsingle (Var (BaseRref $ GroundRscalar tp) ref)
        Just _ -> internalError "Illegal variable"
        Nothing -> internalError "Variable not found"
    in
      AwhileInputOutput
        (InputOutputRpair InputOutputRsignal InputOutputRref)
        -- Input
        (weakenSucc $ weakenSucc weakenId)
        (LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle (BaseRref groundR))
        (\k -> env (weakenSucc $ weakenSucc k) `PPush` FutureScalar tp (k >:> SuccIdx ZeroIdx) (k >:> ZeroIdx))
        initial
        -- Output
        (OutputEnvScalar tp)

data AwhileInputOutput fenv0 fenv genv t where
  AwhileInputOutput
    :: InputOutputR input output
    -- Input
    -> (fenv :> fenv')
    -> BLeftHandSide input fenv fenv'
    -> (forall fenv''. fenv' :> fenv'' -> FutureEnv fenv'' genv')
    -> BaseVars fenv0 input
    -- Output
    -> OutputEnv t output
    -> AwhileInputOutput fenv0 fenv genv t


{-

  Awhile  :: InputOutputR input output
          -> UniformScheduleFun exe env (input -> Output PrimBool -> ())
          -> UniformScheduleFun exe env (input -> output -> ())
          -> BaseVars env input
          -> UniformSchedule exe env -- Operations after the while loop
          -> UniformSchedule exe env
-}

matchOutputEnvWithEnv :: OutputEnv t r -> PartialDoOutput fenv fenv' t r' -> Maybe (r :~: r')
matchOutputEnvWithEnv (OutputEnvPair v1 v2) (PartialDoOutputPair e1 e2)
  | Just Refl <- matchOutputEnvWithEnv v1 e1
  , Just Refl <- matchOutputEnvWithEnv v2 e2               = Just Refl
matchOutputEnvWithEnv OutputEnvShared{} PartialDoOutputShared{} = Just Refl
matchOutputEnvWithEnv OutputEnvUnique{} PartialDoOutputUnique{} = Just Refl
matchOutputEnvWithEnv OutputEnvIgnore   PartialDoOutputUnit     = Just Refl
matchOutputEnvWithEnv _                  _                 = Nothing

partialDoSubstituteOutput :: forall fenv fenv' t r. PartialDoOutput () fenv t r -> BaseVars fenv' r -> Env (NewIdx fenv') fenv
partialDoSubstituteOutput = go Empty
  where
    go :: Env (NewIdx fenv') fenv1 -> PartialDoOutput fenv1 fenv2 t' r' -> BaseVars fenv' r' -> Env (NewIdx fenv') fenv2
    go env (PartialDoOutputPair o1 o2) (TupRpair v1 v2)
      = go (go env o1 v1) o2 v2
    go env PartialDoOutputUnit TupRunit
      = env
    go env (PartialDoOutputScalar _) (TupRpair (TupRsingle v1) (TupRsingle v2))
      = env `Push` NewIdxJust (varIdx v2) `Push` NewIdxJust (varIdx v1)
    go env (PartialDoOutputShared _) (TupRpair (TupRpair (TupRsingle v1) (TupRsingle v2)) (TupRsingle v3))
      = env `Push` NewIdxJust (varIdx v3) `Push` NewIdxJust (varIdx v2) `Push` NewIdxJust (varIdx v1)
    go env (PartialDoOutputUnique _) (TupRpair (TupRpair (TupRpair (TupRsingle v1) (TupRsingle v2)) (TupRsingle v3)) (TupRsingle v4))
      = env `Push` NewIdxJust (varIdx v4) `Push` NewIdxJust (varIdx v3) `Push` NewIdxJust (varIdx v2) `Push` NewIdxJust (varIdx v1)
    go _ _ _ = internalError "Impossible BaseVars"

partialDoSubstituteConvertEnv :: forall genv fenv1 fenv2 fenv' t r. ConvertEnv genv fenv1 fenv2 -> FutureEnv fenv' genv -> Env (NewIdx fenv') fenv1 -> Env (NewIdx fenv') fenv2
partialDoSubstituteConvertEnv ConvertEnvNil _ env = env
partialDoSubstituteConvertEnv (ConvertEnvSeq c1 c2) fenv env = partialDoSubstituteConvertEnv c2 fenv $ partialDoSubstituteConvertEnv c1 fenv env
partialDoSubstituteConvertEnv (ConvertEnvAcquire (Acquire m var)) fenv env
  | Just (FutureBuffer _ _ _ read mWrite) <- prjPartial (varIdx var) fenv =
    let
      lock
        | In <- m = read
        | Just write <- mWrite = write
        | otherwise = internalError "Requested write access to a buffer, but the FutureBuffer only has read permissions"
      (signal, resolver)
        | Borrow s r <- lock = (NewIdxJust s, NewIdxJust r)
        | Move   s   <- lock = (NewIdxJust s, NewIdxNoResolver)
    in
      env `Push` signal `Push` resolver
  | otherwise = internalError "Requested access to a buffer, but the FutureBuffer was not found in the environment"
partialDoSubstituteConvertEnv (ConvertEnvFuture var) fenv env
  | Just future <- prjPartial (varIdx var) fenv =
    let
      (signal, ref)
        | FutureScalar _ s r     <- future = (s, r)
        | FutureBuffer _ s r _ _ <- future = (s, r)
    in
      env `Push` NewIdxJust signal `Push` NewIdxJust ref
  | otherwise = internalError "Requested access to a value, but the Future was not found in the environment"

forks :: [UniformSchedule (Cluster op) fenv] -> UniformSchedule (Cluster op) fenv
forks [] = Return
forks [u] = u
forks (u:us) = Fork (forks us) u

serial :: forall op fenv. [UniformSchedule (Cluster op) fenv] -> UniformSchedule (Cluster op) fenv
serial = go weakenId
  where
    go :: forall fenv1. fenv :> fenv1 -> [UniformSchedule (Cluster op) fenv] -> UniformSchedule (Cluster op) fenv1
    go _  [] = Return
    go k1 (u:us) = trav k1 (weaken' k1 u)
      where
        trav :: forall fenv'. fenv :> fenv' -> UniformSchedule (Cluster op) fenv' -> UniformSchedule (Cluster op) fenv'
        trav k = \case
          Return -> go k us
          Alet lhs bnd u' -> Alet lhs bnd $ trav (weakenWithLHS lhs .> k) u'
          Effect effect u' -> Effect effect $ trav k u'
          Acond cond true false u' -> Acond cond true false $ trav k u'
          Awhile io f input u' -> Awhile io f input $ trav k u'
          Fork u' u'' -> Fork (trav k u') u''

data DeclareInput fenv genv' t where
  DeclareInput :: fenv :> fenv'
               -> BLeftHandSide (Input t) fenv fenv'
               -> (forall fenv''. fenv' :> fenv'' -> FutureEnv fenv'' genv')
               -> DeclareInput fenv genv' t

declareInput
  :: forall t fenv genv genv'.
     FutureEnv fenv genv
  -> GLeftHandSide t genv genv'
  -> DeclareInput fenv genv' t
declareInput = \fenv -> go weakenId (\k -> mapPartialEnv (weaken k) fenv)
  where
    go :: forall fenv' genv1 genv2 s. fenv :> fenv' -> (forall fenv''. fenv' :> fenv'' -> FutureEnv fenv'' genv1) -> GLeftHandSide s genv1 genv2 -> DeclareInput fenv' genv2 s
    go k fenv (LeftHandSidePair lhs1 lhs2)
      | DeclareInput k1 lhs1' fenv1 <- go k         fenv  lhs1
      , DeclareInput k2 lhs2' fenv2 <- go (k1 .> k) fenv1 lhs2
      = DeclareInput (k2 .> k1) (LeftHandSidePair lhs1' lhs2') fenv2
    go _ fenv (LeftHandSideWildcard grounds) = DeclareInput weakenId (LeftHandSideWildcard $ inputR grounds) fenv
    go k fenv (LeftHandSideSingle (GroundRscalar tp)) -- Scalar
      | Refl <- inputSingle $ GroundRscalar tp
      = DeclareInput
          (weakenSucc $ weakenSucc weakenId)
          (LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle (BaseRref $ GroundRscalar tp))
          (\k' -> PPush (fenv $ weakenSucc $ weakenSucc k')
                    $ FutureScalar
                        tp
                        (k' >:> SuccIdx ZeroIdx)
                        (k' >:> ZeroIdx))
    go k fenv (LeftHandSideSingle (GroundRbuffer tp)) -- Buffer
      = DeclareInput
          (weakenSucc $ weakenSucc weakenId)
          (LeftHandSideSingle BaseRsignal `LeftHandSidePair` LeftHandSideSingle (BaseRref $ GroundRbuffer tp))
          (\k' -> PPush (fenv $ weakenSucc $ weakenSucc k')
                    $ FutureBuffer
                        tp
                        (k' >:> SuccIdx ZeroIdx)
                        (k' >:> ZeroIdx)
                        (Move $ (k' >:> (SuccIdx ZeroIdx)))
                        Nothing)

data DeclareOutput op fenv t where
  DeclareOutput :: fenv :> fenv'
                -> BLeftHandSide (Output t) fenv fenv'
                -> fenv' :> fenv''
                -> (UniformSchedule (Cluster op) fenv'' -> UniformSchedule (Cluster op) fenv')
                -> OutputEnv t r
                -> (forall fenv'''. fenv'' :> fenv''' -> BaseVars fenv''' r)
                -> DeclareOutput op fenv t

data DeclareOutputInternal op fenv' t where
  DeclareOutputInternal :: fenv' :> fenv''
                        -> (UniformSchedule (Cluster op) fenv'' -> UniformSchedule (Cluster op) fenv')
                        -> OutputEnv t r
                        -> (forall fenv'''. fenv'' :> fenv''' -> BaseVars fenv''' r)
                        -> DeclareOutputInternal op fenv' t

declareOutput
  :: forall op fenv t.
     GroundsR t
  -> DeclareOutput op fenv t
declareOutput grounds
  | DeclareVars lhs k1 value <- declareVars $ outputR grounds
  , DeclareOutputInternal k2 instr outputEnv outputVars <- go weakenId grounds (value weakenId)
  = DeclareOutput k1 lhs k2 instr outputEnv outputVars
  where
    go :: fenv1 :> fenv2 -> GroundsR s -> BaseVars fenv1 (Output s) -> DeclareOutputInternal op fenv2 s
    go _ TupRunit TupRunit
      = DeclareOutputInternal
          weakenId
          id
          OutputEnvIgnore
          $ const TupRunit
    go k (TupRpair gL gR) (TupRpair vL vR)
      | DeclareOutputInternal kL instrL outL varsL' <- go k         gL vL
      , DeclareOutputInternal kR instrR outR varsR' <- go (kL .> k) gR vR
      = DeclareOutputInternal
          (kR .> kL)
          (instrL . instrR)
          (OutputEnvPair outL outR)
          $ \k' -> varsL' (k' .> kR) `TupRpair` varsR' k'
    go k (TupRsingle (GroundRbuffer tp)) (TupRsingle signal `TupRpair` TupRsingle ref)
      = DeclareOutputInternal
          (weakenSucc $ weakenSucc weakenId)
          (Alet lhsSignal NewSignal)
          OutputEnvShared
          $ \k' ->
            let k'' = k' .> weakenSucc' (weakenSucc' k)
            in TupRsingle (Var BaseRsignalResolver $ weaken k' ZeroIdx)
                `TupRpair` TupRsingle (weaken k'' signal)
                `TupRpair` TupRsingle (weaken k'' ref)
    go k (TupRsingle (GroundRscalar tp)) vars
      | Refl <- inputSingle $ GroundRscalar tp
      , TupRsingle signal `TupRpair` TupRsingle ref <- vars
      = DeclareOutputInternal
          weakenId
          id
          (OutputEnvScalar tp)
          $ \k' ->
            let k'' = k' .> k
            in TupRsingle (weaken k'' signal)
                `TupRpair` TupRsingle (weaken k'' ref)


data DeclareBinding op fenv genv' t where
  DeclareBinding :: fenv :> fenv'
                 -> (UniformSchedule (Cluster op) fenv' -> UniformSchedule (Cluster op) fenv)
                 -> OutputEnv t r
                 -> (forall fenv''. fenv' :> fenv'' -> BaseVars fenv'' r)
                 -> (forall fenv''. fenv' :> fenv'' -> FutureEnv fenv'' genv')
                 -> DeclareBinding op fenv genv' t

declareBinding
  :: forall op fenv genv genv' bnd ret ret'.
     OutputEnv ret ret'
  -> BaseVars fenv ret'
  -> FutureEnv fenv genv
  -> GLeftHandSide bnd genv genv'
  -> TupR (Destination ret) bnd
  -> TupR Uniqueness bnd
  -> DeclareBinding op fenv genv' bnd
declareBinding retEnv retVars = \fenv -> go weakenId (\k -> mapPartialEnv (weaken k) fenv)
  where
    go :: forall fenv' genv1 genv2 t. fenv :> fenv' -> (forall fenv''. fenv' :> fenv'' -> FutureEnv fenv'' genv1) -> GLeftHandSide t genv1 genv2 -> TupR (Destination ret) t -> TupR Uniqueness t -> DeclareBinding op fenv' genv2 t
    go k fenv (LeftHandSidePair lhs1 lhs2) (TupRpair dest1 dest2) (TupRpair u1 u2)
      | DeclareBinding k1 instr1 out1 vars1 fenv1 <- go k         fenv  lhs1 dest1 u1
      , DeclareBinding k2 instr2 out2 vars2 fenv2 <- go (k1 .> k) fenv1 lhs2 dest2 u2
      = DeclareBinding (k2 .> k1) (instr1 . instr2) (OutputEnvPair out1 out2) (\k' -> TupRpair (vars1 $ k' .> k2) (vars2 k')) fenv2
    go k fenv (LeftHandSideWildcard _) _ _
      = DeclareBinding
          weakenId
          id
          OutputEnvIgnore
          (const TupRunit)
          fenv
    go k fenv (LeftHandSideSingle _) (TupRsingle (DestinationReuse idx)) _
      = DeclareBinding
          weakenId
          id
          OutputEnvIgnore
          (const TupRunit)
          (\k' -> PNone $ fenv k')
    go k fenv (LeftHandSideSingle (GroundRscalar tp)) _ _
      = DeclareBinding
          (weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId)
          instr
          (OutputEnvScalar tp)
          (\k' -> TupRpair
                    (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx2)
                    (TupRsingle $ Var (BaseRrefWrite $ GroundRscalar tp) $ k' >:> idx0))
          (\k' -> PPush (fenv $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc k')
                    $ FutureScalar
                        tp
                        (k' >:> idx3)
                        (k' >:> idx1))
      where
        instr
          = Alet lhsSignal NewSignal
          . Alet (lhsRef $ GroundRscalar tp) (NewRef $ GroundRscalar tp)
        
        idx0 = ZeroIdx
        idx1 = SuccIdx ZeroIdx
        idx2 = SuccIdx $ SuccIdx ZeroIdx
        idx3 = SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    go k fenv (LeftHandSideSingle (GroundRbuffer tp)) _ (TupRsingle Unique)
      = DeclareBinding
          (weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId)
          instr
          OutputEnvUnique
          (\k' -> TupRpair
                    ( TupRpair
                      ( TupRpair
                        (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx6)
                        (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx4)
                      )
                      (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx2)
                    )
                    (TupRsingle $ Var (BaseRrefWrite $ GroundRbuffer tp) $ k' >:> idx0))
          (\k' -> PPush (fenv $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc k')
                    $ FutureBuffer
                        tp
                        (k' >:> idx7)
                        (k' >:> idx1)
                        (Move (k' >:> idx5))
                        $ Just $ Move $ k' >:> idx3)
      where
        instr
          = Alet lhsSignal NewSignal -- Signal to grant access to the reference (idx7, idx6)
          . Alet lhsSignal NewSignal -- Signal to grant read access to the array (idx5, idx4)
          . Alet lhsSignal NewSignal -- Signal to grant write access to the array (idx3, idx2)
          . Alet (lhsRef $ GroundRbuffer tp) (NewRef $ GroundRbuffer tp) -- (idx1, idx0)
        
        idx0 = ZeroIdx
        idx1 = SuccIdx ZeroIdx
        idx2 = SuccIdx $ SuccIdx ZeroIdx
        idx3 = SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx4 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx5 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx6 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx7 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
    go k fenv (LeftHandSideSingle (GroundRbuffer tp)) _ (TupRsingle Shared)
      = DeclareBinding
          (weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc weakenId)
          instr
          OutputEnvShared
          (\k' -> TupRpair
                    ( TupRpair
                      (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx4)
                      (TupRsingle $ Var BaseRsignalResolver $ k' >:> idx2)
                    )
                    (TupRsingle $ Var (BaseRrefWrite $ GroundRbuffer tp) $ k' >:> idx0))
          (\k' -> PPush (fenv $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc $ weakenSucc k')
                    $ FutureBuffer
                        tp
                        (k' >:> idx5)
                        (k' >:> idx1)
                        (Move (k' >:> idx3))
                        Nothing)
      where
        instr
          = Alet lhsSignal NewSignal
          . Alet lhsSignal NewSignal
          . Alet (lhsRef $ GroundRbuffer tp) (NewRef $ GroundRbuffer tp)
        
        idx0 = ZeroIdx
        idx1 = SuccIdx ZeroIdx
        idx2 = SuccIdx $ SuccIdx ZeroIdx
        idx3 = SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx4 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx
        idx5 = SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx $ SuccIdx ZeroIdx

type ReindexPartialN f env env' = forall a. Idx env a -> f (NewIdx env' a)

data NewIdx env t where
  NewIdxNoResolver :: NewIdx env SignalResolver
  NewIdxJust :: Idx env t -> NewIdx env t

data SunkReindexPartialN f env env' where
  Sink     :: SunkReindexPartialN f env env' -> SunkReindexPartialN f (env, s) (env', s)
  ReindexF :: ReindexPartialN f env env' -> SunkReindexPartialN f env env'


reindexSchedule :: (IsExecutableAcc exe, Applicative f) => ReindexPartialN f env env' -> UniformSchedule exe env -> f (UniformSchedule exe env')
reindexSchedule k = reindexSchedule' $ ReindexF k

sinkReindexWithLHS :: LeftHandSide s t env1 env1' -> LeftHandSide s t env2 env2' -> SunkReindexPartialN f env1 env2 -> SunkReindexPartialN f env1' env2'
sinkReindexWithLHS (LeftHandSideWildcard _) (LeftHandSideWildcard _) k = k
sinkReindexWithLHS (LeftHandSideSingle _)   (LeftHandSideSingle _)   k = Sink k
sinkReindexWithLHS (LeftHandSidePair a1 b1) (LeftHandSidePair a2 b2) k = sinkReindexWithLHS b1 b2 $ sinkReindexWithLHS a1 a2 k
sinkReindexWithLHS _ _ _ = error "sinkReindexWithLHS: left hand sides don't match"

reindex' :: Applicative f => SunkReindexPartialN f env env' -> ReindexPartialN f env env'
reindex' (ReindexF f) = f
reindex' (Sink k) = \case
  ZeroIdx    -> pure $ NewIdxJust ZeroIdx
  SuccIdx ix ->
    let
      f NewIdxNoResolver = NewIdxNoResolver
      f (NewIdxJust ix') = NewIdxJust $ SuccIdx ix'
    in
      f <$> reindex' k ix

reindexSchedule' :: (IsExecutableAcc exe, Applicative f) => SunkReindexPartialN f env env' -> UniformSchedule exe env -> f (UniformSchedule exe env')
reindexSchedule' k = \case
  Return -> pure Return
  Alet lhs bnd s
    | Exists lhs' <- rebuildLHS lhs -> Alet lhs' <$> reindexBinding' k bnd <*> reindexSchedule' (sinkReindexWithLHS lhs lhs' k) s
  Effect effect s -> Effect <$> reindexEffect' k effect <*> reindexSchedule' k s
  Acond cond t f continue -> Acond <$> reindexVarUnsafe k cond <*> reindexSchedule' k t <*> reindexSchedule' k f <*> reindexSchedule' k continue
  Awhile io f init continue -> Awhile io <$> reindexScheduleFun' k f <*> traverseTupR (reindexVarUnsafe k) init <*> reindexSchedule' k continue
  Fork s1 s2 -> Fork <$> reindexSchedule' k s1 <*> reindexSchedule' k s2

reindexVarUnsafe :: Applicative f => SunkReindexPartialN f env env' -> Var s env t -> f (Var s env' t)
reindexVarUnsafe k (Var tp idx) = Var tp . fromNewIdxUnsafe <$> reindex' k idx

reindexScheduleFun' :: (IsExecutableAcc exe, Applicative f) => SunkReindexPartialN f env env' -> UniformScheduleFun exe env t -> f (UniformScheduleFun exe env' t)
reindexScheduleFun' k = \case
  Sbody s -> Sbody <$> reindexSchedule' k s
  Slam lhs f
    | Exists lhs' <- rebuildLHS lhs -> Slam lhs' <$> reindexScheduleFun' (sinkReindexWithLHS lhs lhs' k) f

reindexEffect' :: forall exe f env env'. (IsExecutableAcc exe, Applicative f) => SunkReindexPartialN f env env' -> Effect exe env -> f (Effect exe env')
reindexEffect' k = \case
  Exec exe -> Exec <$> reindexExecPartial (fromNewIdxUnsafe <.> reindex' k) exe
  SignalAwait signals -> SignalAwait <$> traverse (fromNewIdxSignal <.> reindex' k) signals
  SignalResolve resolvers -> SignalResolve . mapMaybe toMaybe <$> traverse (reindex' k) resolvers
  RefWrite ref value -> RefWrite <$> reindexVar (fromNewIdxOutputRef <.> reindex' k) ref <*> reindexVar (fromNewIdxUnsafe <.> reindex' k) value
  where
    toMaybe :: NewIdx env' a -> Maybe (Idx env' a)
    toMaybe (NewIdxJust idx) = Just idx
    toMaybe _ = Nothing

-- For Exec we cannot have a safe function from the conversion,
-- as we cannot enforce in the type system that no SignalResolvers
-- occur in an Exec or Compute.
fromNewIdxUnsafe :: NewIdx env' a -> Idx env' a
fromNewIdxUnsafe (NewIdxJust idx) = idx
fromNewIdxUnsafe _ = error "Expected NewIdxJust"

-- Different versions, which have different ways of getting evidence
-- that NewIdxNoResolver is impossible
fromNewIdxSignal :: NewIdx env' Signal -> Idx env' Signal
fromNewIdxSignal (NewIdxJust idx) = idx

fromNewIdxOutputRef :: NewIdx env' (OutputRef t) -> Idx env' (OutputRef t)
fromNewIdxOutputRef (NewIdxJust idx) = idx

fromNewIdxRef :: NewIdx env' (Ref t) -> Idx env' (Ref t)
fromNewIdxRef (NewIdxJust idx) = idx

fromNewIdxGround :: GroundR a -> NewIdx env' a -> Idx env' a
fromNewIdxGround _  (NewIdxJust idx) = idx
fromNewIdxGround tp NewIdxNoResolver = signalResolverImpossible (TupRsingle tp)

reindexBinding' :: Applicative f => SunkReindexPartialN f env env' -> Binding env t -> f (Binding env' t)
reindexBinding' k = \case
  Compute e -> Compute <$> reindexExp (fromNewIdxUnsafe <.> reindex' k) e
  NewSignal -> pure NewSignal
  NewRef tp -> pure $ NewRef tp
  Alloc shr tp sh -> Alloc shr tp <$> reindexVars (fromNewIdxUnsafe <.> reindex' k) sh
  Use tp buffer -> pure $ Use tp buffer
  Unit (Var tp idx) -> Unit . Var tp <$> (fromNewIdxGround (GroundRscalar tp) <.> reindex' k) idx
  RefRead ref -> RefRead <$> reindexVar (fromNewIdxUnsafe <.> reindex' k) ref

(<.>) :: Applicative f => (b -> c) -> (a -> f b) -> a -> f c
(<.>) g h a = g <$> h a
