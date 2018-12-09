module Juvix.Backends.Michelson.Transpilation.Expr where

import           Control.Monad.State
import           Control.Monad.Writer
import qualified Data.Text                                    as T
import           Protolude

import           Juvix.Backends.Michelson.Transpilation.Types
import qualified Juvix.Backends.Michelson.Untyped             as M
import           Juvix.Lang
import           Juvix.Utility

import qualified Idris.Core.TT                                as I
import qualified IRTS.Lang                                    as I

exprToMichelson ∷ ∀ m . (MonadWriter [TranspilationLog] m, MonadError TranspilationError m, MonadState M.Stack m) ⇒ Expr → m (M.Expr, M.Type)
exprToMichelson expr = (,) <$> exprToExpr expr <*> exprToType expr

{-
 - Transform core expression to Michelson instruction sequence.
 - This requires tracking the stack state.
 - At the moment, this functions maintains a forward mapping from the Haskell expression type and the Michelson stack type.
 - ∷ { Haskell Type } ~ { Stack Pre-Evaluation } ⇒ { Stack Post-Evaluation }
 -}

exprToExpr ∷ ∀ m . (MonadWriter [TranspilationLog] m, MonadError TranspilationError m, MonadState M.Stack m) ⇒ Expr → m M.Expr
exprToExpr expr = do

  let tellReturn ∷ M.Expr → m M.Expr
      tellReturn ret = tell [ExprToExpr expr ret] >> return ret

      notYetImplemented ∷ m M.Expr
      notYetImplemented = throw (NotYetImplemented $ prettyPrintValue expr)

      failWith ∷ Text → m M.Expr
      failWith = throw . NotYetImplemented

  case expr of

    -- :: a ~ s => (a, s)
    I.LV name            -> do
      -- TODO: Find variable on stack, rearrange.
      notYetImplemented

    -- ∷ (\a → b) a ~ s ⇒ (b, s)
    I.LApp _ func args   -> do
      -- TODO: Sequence
      notYetImplemented

    -- ∷ (\a → b) a ~ s ⇒ (b, s)
    I.LLazyApp func args -> notYetImplemented

    -- :: a ~ s => (a, s)
    I.LLazyExp expr      -> exprToExpr expr

    -- :: a ~ s => (a, s)
    I.LForce expr        -> exprToExpr expr

    -- :: a ~ s => (a, s)
    I.LLet name val expr -> notYetImplemented

    -- ∷ \a... → b ~ (a..., s) ⇒ (b, s)
    I.LLam args body     -> do
      forM_ args (\a -> modify ((:) (M.VarE $ prettyPrintValue a)))
      exprToExpr body

    -- ??
    I.LProj expr num     -> notYetImplemented

    I.LCon _ _ name args -> do
      -- TODO: Typeconvert into representation type.
      notYetImplemented

    -- ∷ a ~ s ⇒ (a, s)
    I.LCase ct expr alts -> do
      -- TODO: Case switch.
      notYetImplemented

    -- ∷ a ~ s ⇒ (a, s)
    I.LConst const       -> do
      -- TODO: Convert.
      notYetImplemented

    -- (various)
    I.LForeign _ _ _     -> notYetImplemented

    -- (various)
    I.LOp prim exprs     -> notYetImplemented

    I.LNothing           -> notYetImplemented

    I.LError msg         -> failWith (T.pack msg)

exprToType ∷ ∀ m . (MonadWriter [TranspilationLog] m, MonadError TranspilationError m) ⇒ Expr → m M.Type
exprToType expr = do
  -- TODO: Lookup type from Idris. May need to inject before type erasure.
  return (M.LamT (M.PairT M.StringT M.StringT) (M.PairT M.StringT M.StringT))

primToExpr ∷ ∀ m . (MonadWriter [TranspilationLog] m, MonadError TranspilationError m, MonadState M.Stack m) ⇒ Prim → m M.Expr
primToExpr prim = do
  let notYetImplemented ∷ m M.Expr
      notYetImplemented = throw (NotYetImplemented $ prettyPrintValue prim)

  case prim of
    I.LPlus (I.ATInt I.ITBig)  -> return M.AddIntInt
    I.LMinus (I.ATInt I.ITBig) -> return M.SubInt

    _                          -> notYetImplemented
