-- |
-- Module      : Data.Array.Accelerate.CUDA.CodeGen.Skeleton
-- Copyright   : [2008..2011] Manuel M T Chakravarty, Gabriele Keller, Sean Lee, Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Manuel M T Chakravarty <chak@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--
-- Constructors for array computation skeletons
--

module Data.Array.Accelerate.CUDA.CodeGen.Skeleton
  (
    mkGenerate, mkFold, mkFold1, mkFoldSeg, mkFold1Seg, mkMap, mkZipWith,
    mkStencil, mkStencil2,
    mkScanl, mkScanr, mkScanl', mkScanr', mkScanl1, mkScanr1,
    mkPermute, mkBackpermute, mkIndex, mkReplicate
  )
  where

import Language.C
import System.FilePath
import Data.Array.Accelerate.CUDA.CodeGen.Data
import Data.Array.Accelerate.CUDA.CodeGen.Util
import Data.Array.Accelerate.CUDA.CodeGen.Tuple

-- Construction
-- ------------

mkGenerate :: ([CType],Int) -> [CExpr] -> CUTranslSkel
mkGenerate (tyOut, dimOut) apply = CUTranslSkel code [] skel
  where
    skel = "generate.inl"
    code = CTranslUnit
            ( mkTupleType Nothing  tyOut ++
            [ mkDim "DimOut" dimOut
	    , mkDim "TyIn0"  dimOut
            , mkApply 1 apply ])
            (mkNodeInfo (initPos skel) (Name 0))


-- Reduction
-- ---------

mkFold :: ([CType],Int) -> [CExpr] -> [CExpr] -> CUTranslSkel
mkFold (ty,dim) identity apply = CUTranslSkel code [] skel
  where
    skel | dim == 1  = "foldAll.inl"
         | otherwise = "fold.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkTuplePartition "ArrOut" ty True
            , mkIdentity identity
            , mkApply 2 apply
            , mkDim "DimIn0" dim
            , mkDim "DimOut" (dim-1) ])
            (mkNodeInfo (initPos skel) (Name 0))

mkFold1 :: ([CType],Int) -> [CExpr] -> CUTranslSkel
mkFold1 (ty,dim) apply = CUTranslSkel code inc skel
  where
    skel | dim == 1  = "foldAll.inl"
         | otherwise = "fold.inl"
    inc  = [(internalIdent "INCLUSIVE", Just (fromBool True))]
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkTuplePartition "ArrOut" ty True
            , mkApply 2 apply
            , mkDim "DimIn0" dim
            , mkDim "DimOut" (dim-1) ])
            (mkNodeInfo (initPos skel) (Name 0))

mkFoldSeg :: ([CType],Int) -> [CType] -> [CExpr] -> [CExpr] -> CUTranslSkel
mkFoldSeg (ty,dim) int identity apply = CUTranslSkel code [] skel
  where
    skel = "foldSeg.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkTuplePartition "ArrOut" ty True
            , mkIdentity identity
            , mkApply 2 apply
            , mkTypedef "Int" False False (head int)
            , mkDim "DimIn0" dim
            , mkDim "DimOut" dim ])
            (mkNodeInfo (initPos skel) (Name 0))

mkFold1Seg :: ([CType],Int) -> [CType] -> [CExpr] -> CUTranslSkel
mkFold1Seg (ty,dim) int apply = CUTranslSkel code inc skel
  where
    skel = "foldSeg.inl"
    inc  = [(internalIdent "INCLUSIVE", Just (fromBool True))]
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkTuplePartition "ArrOut" ty True
            , mkApply 2 apply
            , mkTypedef "Int" False False (head int)
            , mkDim "DimIn0" dim
            , mkDim "DimOut" dim ])
            (mkNodeInfo (initPos skel) (Name 0))


-- Map
-- ---

mkMap :: [CType] -> [CType] -> [CExpr] -> CUTranslSkel
mkMap tyOut tyIn0 apply = CUTranslSkel code [] skel
  where
    skel = "map.inl"
    code = CTranslUnit
            ( mkTupleType Nothing  tyOut ++
              mkTupleType (Just 0) tyIn0 ++
            [ mkApply 1 apply ])
            (mkNodeInfo (initPos skel) (Name 0))


mkZipWith :: ([CType], Int) -> ([CType], Int) -> ([CType], Int) -> [CExpr] -> CUTranslSkel
mkZipWith (tyOut,dimOut) (tyIn1,dimIn1) (tyIn0,dimIn0) apply = CUTranslSkel code [] skel
  where
    skel = "zipWith.inl"
    code = CTranslUnit
            ( mkTupleType Nothing  tyOut ++
              mkTupleType (Just 1) tyIn1 ++
              mkTupleType (Just 0) tyIn0 ++
            [ mkApply 2 apply
            , mkDim "DimOut" dimOut
            , mkDim "DimIn1" dimIn1
            , mkDim "DimIn0" dimIn0 ])
            (mkNodeInfo (initPos skel) (Name 0))


-- Stencil
-- -------

mkStencil :: [CType]
          -> [CType] -> [[Int]] -> Either String [CExpr]
          -> [CExpr]
          -> CUTranslSkel
mkStencil tyOut tyIn0 ixs bndy apply = CUTranslSkel code (bndyDef bndy) skel
  where
    skel = "stencil1.inl"
    code = CTranslUnit
            ( mkTupleType Nothing  tyOut ++
              mkTexTupleTypes [tyIn0] ++
              mkStencilType 0 tyIn0 (length ixs) ++
            [ mkDim "DimIn0" (length $ head ixs) ] ++
              mkGatherAndApply tyIn0 ixs apply ++
              bndyConst 0 bndy )
            (mkNodeInfo (initPos skel) (Name 0))

mkStencil2 :: [CType]
           -> [CType] -> [[Int]] -> Either String [CExpr]
           -> [CType] -> [[Int]] -> Either String [CExpr]
           -> [CExpr]
           -> CUTranslSkel
mkStencil2 tyOut tyIn0 ixs0 bndy0 tyIn1 ixs1 bndy1 apply
  = CUTranslSkel code (bndyDef bndy0 ++ bndyDef bndy1) skel
  where
    skel = "stencil2.inl"
    code = CTranslUnit
            ( mkTupleType Nothing  tyOut ++
              mkTexTupleTypes [tyIn0, tyIn1] ++
              mkStencilType 0 tyIn0 (length ixs0) ++
              mkStencilType 1 tyIn1 (length ixs1) ++
            [ mkDim "DimOut" (length $ head ixs0),   -- all dimensions the same
              mkDim "DimIn0" (length $ head ixs0),
              mkDim "DimIn1" (length $ head ixs1) ] ++
              mkGatherAndApply2 tyIn0 ixs0 tyIn1 ixs1 apply ++
              bndyConst 0 bndy0 ++
              bndyConst 1 bndy1 )
            (mkNodeInfo (initPos skel) (Name 0))

--
bndyDef :: Either String [CExpr] -> [CMacro]
bndyDef bndy =
  case bndy of
    Left bndyTy -> [(internalIdent bndyTy, Nothing)]
    Right _     -> []

bndyConst :: Int -> Either String [CExpr] -> [CExtDecl]
bndyConst n bndy =
  case bndy of
    Left _  -> []
    Right c -> [mkDeviceFun ("boundary_const" ++ show n) (typename ("TyIn" ++ show n)) [] c]


-- Scan
-- ----

-- TODO: use a fast scan for primitive types
--
mkExclusiveScan :: Bool -> Bool -> [CType] -> [CExpr] -> [CExpr] -> CUTranslSkel
mkExclusiveScan isReverse isHaskellStyle ty identity apply = CUTranslSkel code defs skel
  where
    skel = "scan.inl"
    defs = [(internalIdent "REVERSE",       Just (fromBool isReverse))
           ,(internalIdent "HASKELL_STYLE", Just (fromBool isHaskellStyle))]
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkIdentity identity
            , mkApply 2 apply ])
            (mkNodeInfo (initPos (takeFileName skel)) (Name 0))

mkInclusiveScan :: Bool -> [CType] -> [CExpr] -> CUTranslSkel
mkInclusiveScan isReverse ty apply = CUTranslSkel code [rev] skel
  where
    skel = "scan1.inl"
    rev  = (internalIdent "REVERSE", Just (fromBool isReverse))
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkApply 2 apply ])
            (mkNodeInfo (initPos (takeFileName skel)) (Name 0))

mkScanl, mkScanr :: [CType] -> [CExpr] -> [CExpr] -> CUTranslSkel
mkScanl = mkExclusiveScan False True
mkScanr = mkExclusiveScan True  True

mkScanl', mkScanr' :: [CType] -> [CExpr] -> [CExpr] -> CUTranslSkel
mkScanl' = mkExclusiveScan False False
mkScanr' = mkExclusiveScan True  False

mkScanl1, mkScanr1 :: [CType] -> [CExpr] -> CUTranslSkel
mkScanl1 = mkInclusiveScan False
mkScanr1 = mkInclusiveScan True


-- Permutation
-- -----------

mkPermute :: [CType] -> Int -> Int -> [CExpr] -> [CExpr] -> CUTranslSkel
mkPermute ty dimOut dimIn0 combinefn indexfn = CUTranslSkel code [] skel
  where
    skel = "permute.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 2 ty ++
            [ mkDim "DimOut" dimOut
            , mkDim "DimIn0" dimIn0
            , mkProject Forward indexfn
            , mkApply 2 combinefn ])
            (mkNodeInfo (initPos skel) (Name 0))

mkBackpermute :: [CType] -> Int -> Int -> [CExpr] -> CUTranslSkel
mkBackpermute ty dimOut dimIn0 indexFn = CUTranslSkel code [] skel
  where
    skel = "backpermute.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 1 ty ++
            [ mkDim "DimOut" dimOut
            , mkDim "DimIn0" dimIn0
            , mkProject Backward indexFn ])
            (mkNodeInfo (initPos skel) (Name 0))


-- Multidimensional Index and Replicate
-- ------------------------------------

mkIndex :: [CType] -> Int -> Int -> Int -> [CExpr] -> CUTranslSkel
mkIndex ty dimSl dimCo dimIn0 slix = CUTranslSkel code [] skel
  where
    skel = "slice.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 1 ty ++
            [ mkDim "Slice"    dimSl
            , mkDim "CoSlice"  dimCo
            , mkDim "SliceDim" dimIn0
            , mkSliceIndex slix ])
            (mkNodeInfo (initPos skel) (Name 0))


mkReplicate :: [CType] -> Int -> Int -> [CExpr] -> CUTranslSkel
mkReplicate ty dimSl dimOut slix = CUTranslSkel code [] skel
  where
    skel = "replicate.inl"
    code = CTranslUnit
            ( mkTupleTypeAsc 1 ty ++
            [ mkDim "Slice"    dimSl
            , mkDim "SliceDim" dimOut
            , mkSliceReplicate slix ])
            (mkNodeInfo (initPos skel) (Name 0))

