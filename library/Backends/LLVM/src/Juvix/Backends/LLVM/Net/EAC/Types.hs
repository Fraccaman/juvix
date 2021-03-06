module Juvix.Backends.LLVM.Net.EAC.Types where

import qualified Juvix.Backends.LLVM.Codegen as Codegen
import Juvix.Library
-- Abstract out LLVM imports?

import qualified LLVM.AST.AddrSpace as Addr
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.IntegerPredicate as IntPred
import qualified LLVM.AST.Operand as Operand
import qualified LLVM.AST.Type as Type

-- defines a tag over a node type, to denote the variant

tag :: Type.Type
tag = Codegen.i8

tagInt :: Num p => p
tagInt = 8

eacSize :: Num p => p
eacSize = tagInt + Codegen.nodePointerSize

eacNameRef :: Type.Type
eacNameRef = Type.NamedTypeReference eacName

eacName :: IsString p => p
eacName = Codegen.nodeTypeName

eac :: Type.Type
eac = Codegen.nodeType tag []

eacPointer :: Type.Type
eacPointer = Type.PointerType eacNameRef (Addr.AddrSpace 0)

top, app, dup, lam, era :: C.Constant
top = C.Int {C.integerBits = tagInt, C.integerValue = 4}
app = C.Int {C.integerBits = tagInt, C.integerValue = 0}
lam = C.Int {C.integerBits = tagInt, C.integerValue = 1}
era = C.Int {C.integerBits = tagInt, C.integerValue = 2}
dup = C.Int {C.integerBits = tagInt, C.integerValue = 3}

eacListNameRef :: Type.Type
eacListNameRef = Type.NamedTypeReference eacListName

eacListName :: IsString p => p
eacListName = "eac_list"

eacList :: Type.Type
eacList =
  Type.StructureType
    { -- change to true later?
      Type.isPacked = False,
      Type.elementTypes = [eacPointer, eacLPointer]
    }

eacLPointer :: Type.Type
eacLPointer = Type.PointerType eacListNameRef (Addr.AddrSpace 0)

testList :: Type.Type
testList =
  Type.StructureType
    { -- change to true later?
      Type.isPacked = False,
      Type.elementTypes = [Type.i1, testListPointer]
    }

testListPointer :: Type.Type
testListPointer = Type.PointerType (Type.NamedTypeReference "list") (Addr.AddrSpace 0)

--------------------------------------------------------------------------------
-- Node operations
--------------------------------------------------------------------------------

tagOf :: Codegen.RetInstruction m => Operand.Operand -> m Operand.Operand
tagOf eac =
  Codegen.getElementPtr $
    Codegen.Minimal
      { Codegen.type' = Codegen.pointerOf tag,
        Codegen.address' = eac,
        Codegen.indincies' = Codegen.constant32List [0, 0]
      }

--------------------------------------------------------------------------------
-- EacList operations
--------------------------------------------------------------------------------

-- TODO ∷ make sure this works, I doubt it checks null pointers properly
-- probably need a tag to determine when a list is null?
checkNull :: Codegen.RetInstruction m => Operand.Operand -> m Operand.Operand
checkNull xs = do
  xsI <- Codegen.ptrToInt xs (Type.IntegerType Codegen.addressSpace)
  Codegen.icmp
    IntPred.EQ
    ( Operand.ConstantOperand
        ( C.PtrToInt
            (C.Null eacLPointer)
            (Type.IntegerType Codegen.addressSpace)
        )
    )
    xsI

cons :: Codegen.MallocNode m => Operand.Operand -> Operand.Operand -> m Operand.Operand
cons ele eacList = do
  newList <- Codegen.malloc (Codegen.nodePointerSize + Codegen.nodePointerSize) eacLPointer
  car <-
    Codegen.getElementPtr $
      Codegen.Minimal
        { Codegen.type' = Codegen.pointerOf eacPointer,
          Codegen.address' = newList,
          Codegen.indincies' = Codegen.constant32List [0, 0]
        }
  cdr <-
    Codegen.getElementPtr $
      Codegen.Minimal
        { Codegen.type' = Codegen.pointerOf eacLPointer,
          Codegen.address' = newList,
          Codegen.indincies' = Codegen.constant32List [0, 1]
        }
  Codegen.store car ele
  Codegen.store cdr eacList
  pure newList

loadCar :: Codegen.RetInstruction m => Operand.Operand -> m Operand.Operand
loadCar eacList =
  Codegen.loadElementPtr $
    Codegen.Minimal
      { Codegen.type' = eacPointer,
        Codegen.address' = eacList,
        Codegen.indincies' = Codegen.constant32List [0, 0]
      }

loadCdr :: Codegen.RetInstruction m => Operand.Operand -> m Operand.Operand
loadCdr eacList =
  Codegen.loadElementPtr $
    Codegen.Minimal
      { Codegen.type' = eacLPointer,
        Codegen.address' = eacList,
        Codegen.indincies' = Codegen.constant32List [0, 1]
      }

loadList :: Codegen.RetInstruction m => Operand.Operand -> m Operand.Operand
loadList = Codegen.load eacListNameRef
