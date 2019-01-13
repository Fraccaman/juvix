module Juvix.Backends.Michelson.Transpilation.Util where

import           Control.Monad.State
import           Control.Monad.Writer
import           Data.List                                    (elemIndex)
import qualified Data.Text                                    as T
import           Protolude

import           Juvix.Backends.Michelson.Transpilation.Types
import qualified Juvix.Backends.Michelson.Untyped             as M
import           Juvix.Lang
import           Juvix.Utility

pack ∷ forall m . MonadError TranspilationError m ⇒ M.Type → m M.Expr
pack M.UnitT = return (M.Const M.Unit)
pack ty      = throw (NotYetImplemented ("pack: " `T.append` prettyPrintValue ty))

-- Start with value to unpack at top of stack. len (filter Just binds) will be dropped at the end.
unpack ∷ forall m . (MonadError TranspilationError m, MonadState M.Stack m) ⇒ M.Type → [Maybe T.Text] → m M.Expr
unpack ty []          | ty `elem` unitaryTypes = do
  genReturn M.Drop
unpack ty [Nothing]   | ty `elem` unitaryTypes = do
  genReturn M.Drop
unpack ty [Just bind] | ty `elem` unitaryTypes = do
  modify ((:) (M.VarE bind) . drop 1)
  return M.Nop
unpack ty@(M.PairT _ _) binds =
  case binds of
    [Just fst, Just snd] → do
      modify ((<>) [M.VarE fst, M.VarE snd] . drop 1)
      return (M.Seq (M.Seq (M.Seq M.Dup M.Cdr) M.Swap) M.Car)
    [Just fst, Nothing] → do
      modify ((:) (M.VarE fst) . drop 1)
      return M.Car
    [Nothing, Just snd] → do
      modify ((:) (M.VarE snd) . drop 1)
      return M.Cdr
    [Nothing, Nothing]  → do
      genReturn M.Drop
    _ → throw (NotYetImplemented (T.concat ["unpack: ", prettyPrintValue ty, " ~ ", T.intercalate ", " (fmap prettyPrintValue binds)]))
unpack ty binds = throw (NotYetImplemented (T.concat ["unpack: ", prettyPrintValue ty, " ~ ", T.intercalate ", " (fmap prettyPrintValue binds)]))

unpackDrop ∷ forall m . (MonadError TranspilationError m, MonadState M.Stack m) ⇒ [Maybe T.Text] → m M.Expr
unpackDrop binds = genReturn (foldDrop (length (filter isJust binds)))

rearrange ∷ Int → M.Expr
rearrange 0 = M.Nop
rearrange 1 = M.Swap
rearrange n = M.Seq (M.Dip (rearrange (n - 1))) M.Swap

unrearrange ∷ Int → M.Expr
unrearrange 0 = M.Nop
unrearrange 1 = M.Swap
unrearrange n = M.Seq M.Swap (M.Dip (unrearrange (n - 1)))

position ∷ T.Text → M.Stack → Maybe Int
position n = elemIndex (M.VarE n)

dropFirst ∷ T.Text → M.Stack → M.Stack
dropFirst n (x:xs) = if x == M.VarE n then xs else x : dropFirst n xs
dropFirst _ []     = []

foldDrop ∷ Int → M.Expr
foldDrop 0 = M.Nop
foldDrop n = M.Dip (foldl M.Seq M.Nop (replicate n M.Drop))

unitaryTypes ∷ [M.Type]
unitaryTypes = [M.UnitT, M.IntT, M.TezT, M.KeyT]

genReturn ∷ forall m . (MonadError TranspilationError m, MonadState M.Stack m) ⇒ M.Expr → m M.Expr
genReturn expr = do
  modify =<< genFunc expr
  return expr

genFunc ∷ forall m . MonadError TranspilationError m ⇒ M.Expr → m (M.Stack → M.Stack)
genFunc expr = if

  | expr `elem` [M.Nop] → return (\x -> x)

  | expr `elem` [M.Drop] → return (drop 1)
  | expr `elem` [M.Dup] → return (\(x:xs) → x:x:xs)
  | expr `elem` [M.Swap] → return (\(x:y:xs) → y:x:xs)

  | expr `elem` [M.Amount] → return ((:) M.FuncResult)

  | expr `elem` [M.Fail, M.Left, M.Right, M.DefaultAccount, M.Car, M.Cdr, M.Eq, M.Le, M.Not] → return ((:) M.FuncResult . drop 1)

  | expr `elem` [M.MapGet, M.AddIntNat, M.AddNatInt, M.AddNatNat, M.AddIntInt, M.AddTez, M.SubInt, M.SubTez, M.MulIntInt, M.ConsPair] → return ((:) M.FuncResult . drop 2)

  | expr `elem` [M.MapUpdate] → return ((:) M.FuncResult . drop 3)

  | otherwise →
      case expr of

        M.Dip x → do
          f ← genFunc x
          return (\(x:xs) → x : f xs)

        M.Seq x y → do
          x ← genFunc x
          y ← genFunc y
          return (y . x)

        M.Const _ → return ((:) (M.FuncResult))

        _ → throw (NotYetImplemented (T.concat ["genFunc: ", prettyPrintValue expr]))