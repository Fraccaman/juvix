module Juvix.Transpiler.Encoding where

import           Control.Monad.Except
import           Control.Monad.RWS.Strict
import qualified Data.Text                as T
import           Foundation
import qualified Prelude                  as P

import qualified Juvix.Michelson.Script   as M
import           Juvix.Transpiler.Utility
import           Juvix.Types
import           Juvix.Utility

pack ∷ M.Type → CompilerM Expr
pack M.UnitT = return (Lit LUnit)
pack ty      = throwError (NotYetImplemented ("pack: " `T.append` pprint ty))

-- Start with value to unpack at top of stack. len (filter Just binds) will be dropped at the end.

unpack ∷ M.Type → [Maybe T.Text] → CompilerM M.ExprUT
unpack ty []          | ty `elem` unitaryTypes = do
  genReturn M.DropUT
unpack ty [Nothing]   | ty `elem` unitaryTypes = do
  genReturn M.DropUT
unpack ty [Just bind] | ty `elem` unitaryTypes = do
  modify ((:) (BoundVariable bind) . drop 1)
  return M.NopUT
unpack ty@(M.PairT _ _) binds =
  case binds of
    [Just fst, Just snd] → do
      modify ((<>) [BoundVariable fst, BoundVariable snd] . drop 1)
      return (M.SeqUT (M.SeqUT (M.SeqUT M.DupUT M.CdrUT) M.SwapUT) M.CarUT)
    [Just fst, Nothing] → do
      modify ((:) (BoundVariable fst) . drop 1)
      return M.CarUT
    [Nothing, Just snd] → do
      modify ((:) (BoundVariable snd) . drop 1)
      return M.CdrUT
    [Nothing, Nothing]  → do
      genReturn M.DropUT
    _ → throwError (NotYetImplemented (T.concat ["unpack: ", pprint ty, " ~ ", T.intercalate ", " (fmap pprint binds)]))
unpack ty binds = throwError (NotYetImplemented (T.concat ["unpack: ", pprint ty, " ~ ", T.intercalate ", " (fmap pprint binds)]))

unpackDrop ∷ [Maybe T.Text] → CompilerM M.ExprUT
unpackDrop binds = genReturn (foldDrop (P.length (filter isJust binds)))

unitaryTypes ∷ [M.Type]
unitaryTypes = [M.UnitT, M.IntT, M.TezT, M.KeyT]
