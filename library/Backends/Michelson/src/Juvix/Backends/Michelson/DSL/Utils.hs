module Juvix.Backends.Michelson.DSL.Utils where

import qualified Juvix.Backends.Michelson.DSL.Instructions as Instructions
import qualified Juvix.Backends.Michelson.DSL.Untyped as Untyped
import qualified Juvix.Core.ErasedAnn.Types as Ann
import Juvix.Library
import qualified Juvix.Library.NameSymbol as NameSymbol
import qualified Juvix.Library.Usage as Usage
import qualified Michelson.Untyped.Instr as Instr

-- TODO ∷ make usageFromType Fold!

usageFromType :: Ann.Type primTy -> [Usage.T]
usageFromType (Ann.Pi usage _x xs) = usage : usageFromType xs
usageFromType Ann.Sig {} = []
usageFromType Ann.SymT {} = []
usageFromType Ann.Star {} = []
usageFromType Ann.PrimTy {} = []
usageFromType Ann.UnitTy {} = []

piToReturnType :: Ann.Type primTy -> Ann.Type primTy
piToReturnType (Ann.Pi _ _ rest) = piToReturnType rest
piToReturnType last = last

piToList :: Ann.Type primTy -> [(Usage.T, Ann.Type primTy)]
piToList (Ann.Pi usage aType rest) = (usage, aType) : piToList rest
piToList Ann.Sig {} = []
piToList Ann.SymT {} = []
piToList Ann.Star {} = []
piToList Ann.PrimTy {} = []
piToList Ann.UnitTy {} = []

piToListTy :: Ann.Type primTy -> [Ann.Type primTy]
piToListTy (Ann.Pi _usage ty xs) = ty : piToListTy xs
piToListTy Ann.Sig {} = []
piToListTy Ann.SymT {} = []
piToListTy Ann.Star {} = []
piToListTy Ann.PrimTy {} = []
piToListTy Ann.UnitTy {} = []

unpackTuple :: Instr.ExpandedOp
unpackTuple =
  Instructions.dup
    <> Instructions.car
    <> Instructions.dip [Instructions.cdr]

unpackTupleN :: Natural -> Instr.ExpandedOp
unpackTupleN 0 = mempty
unpackTupleN n = unpackTuple <> Instructions.dip [unpackTupleN (pred n)]

-- (captures, args) => args ... : captures ... : []
unpackArgsCaptures :: Natural -> Natural -> Instr.ExpandedOp
unpackArgsCaptures numArgs numCaptures =
  Instructions.dup
    <> Instructions.dip [Instructions.car, unpackTupleN (pred numCaptures)]
    <> Instructions.cdr
    <> unpackTupleN (pred numArgs)

pairN :: Int -> Instr.ExpandedOp
pairN count = fold (replicate count Instructions.pair)

closureType :: [(NameSymbol.T, Untyped.T)] -> Untyped.T
closureType = foldr (Untyped.pair . snd) Untyped.unit

-- | 'lamType' takes Args+Closures and ExtraArgs, along with their return type
-- and constructs a lambda type
lamType :: [(NameSymbol.T, Untyped.T)] -> [(NameSymbol.T, Untyped.T)] -> Untyped.T -> Untyped.T
lamType argsPlusClosures =
  Untyped.lambda
    . Untyped.pair (closureType argsPlusClosures)
    . closureType
