-- |
-- - Entrypoints into compilation from core terms to Michelson terms & contracts.
module Juvix.Backends.Michelson.Compilation where

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text.Lazy as L
import Juvix.Backends.Michelson.Compilation.Types
import qualified Juvix.Backends.Michelson.Compilation.VirtualStack as VStack
import qualified Juvix.Backends.Michelson.DSL.Environment as DSL
import qualified Juvix.Backends.Michelson.DSL.Instructions as DSL
import qualified Juvix.Backends.Michelson.DSL.InstructionsEff as DSL
import qualified Juvix.Backends.Michelson.Optimisation as Optimisation
import qualified Juvix.Core.ErasedAnn.Types as Ann
import Juvix.Core.Usage
import Juvix.Library hiding (Type)
import qualified Michelson.Printer as M
import qualified Michelson.TypeCheck as M
import qualified Michelson.Typed as MT
import qualified Michelson.Untyped as M

typedContractToSource :: M.SomeContract -> Text
typedContractToSource (M.SomeContract (MT.FullContract instr _ _)) =
  L.toStrict (M.printTypedContractCode False instr)

untypedContractToSource :: M.Contract' M.ExpandedOp -> Text
untypedContractToSource c = L.toStrict (M.printUntypedContract False c)

untypedContractToSourceLine :: M.Contract' M.ExpandedOp -> Text
untypedContractToSourceLine c = L.toStrict (M.printUntypedContract True c)

compileContract ::
  Term ->
  (Either DSL.CompError (M.Contract' M.ExpandedOp, M.SomeContract), [CompilationLog])
compileContract term =
  let (ret, env) = DSL.execMichelson (compileToMichelsonContract term)
   in (ret, DSL.compilationLog env)

compileExpr :: Term -> (Either DSL.CompError EmptyInstr, [CompilationLog])
compileExpr term =
  let (ret, env) = DSL.execMichelson (compileToMichelsonExpr term)
   in (ret, DSL.compilationLog env)

compileToMichelsonContract ::
  DSL.Reduction m =>
  Term ->
  m (M.Contract' M.ExpandedOp, M.SomeContract)
compileToMichelsonContract term = do
  let Ann.Ann _ ty _ = term
  michelsonTy <- DSL.typeToPrimType ty
  case michelsonTy of
    M.Type (M.TLambda argTy@(M.Type (M.TPair _ _ paramTy storageTy) _) _) _ -> do
      -- TODO: Figure out what happened to argTy.
      let Ann.Ann _ _ (Ann.LamM _ [name] body) = term
      let paramTy' = M.ParameterType paramTy (M.ann "")
      modify @"stack"
        ( VStack.cons
            ( VStack.VarE
                (Set.singleton name)
                (VStack.Usage Omega VStack.notSaved)
                Nothing,
              argTy
            )
        )
      _ <- DSL.instOuter body
      michelsonOp' <- mconcat |<< get @"ops"
      --
      let michelsonOp = michelsonOp' <> DSL.dip [DSL.drop]
      --
      let contract = M.Contract paramTy' storageTy [michelsonOp]
      --
      case M.typeCheckContract Map.empty contract of
        Right _ -> do
          optimised <- Optimisation.optimise michelsonOp
          let optimisedContract = M.Contract paramTy' storageTy [optimised]
          case M.typeCheckContract Map.empty optimisedContract of
            Right c ->
              pure (optimisedContract, c)
            Left err ->
              throw @"compilationError"
                (DidNotTypecheckAfterOptimisation optimised err)
        Left err ->
          throw @"compilationError" (DidNotTypecheck michelsonOp err)
    _ ->
      throw @"compilationError" (InvalidInputType "not a lambda function")

compileToMichelsonExpr ::
  DSL.Reduction m =>
  Term ->
  m EmptyInstr
compileToMichelsonExpr term = do
  _ <- DSL.instOuter term
  michelsonOp <- mconcat |<< get @"ops"
  case M.runTypeCheckIsolated (M.typeCheckList [michelsonOp] M.SNil) of
    Right (_ M.:/ (s M.::: _)) -> pure (EmptyInstr s)
    -- TODO ∷ Figure out what this case should be
    Right (_ M.:/ (M.AnyOutInstr _)) -> undefined
    Left err -> throw @"compilationError" (DidNotTypecheck michelsonOp err)

runMichelsonExpr :: DSL.Reduction m => NewTerm -> m M.ExpandedOp
runMichelsonExpr = DSL.instOuter
