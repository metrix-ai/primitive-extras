module PrimitiveExtras.Types
where

import PrimitiveExtras.Prelude


newtype PrimMultiArray a = PrimMultiArray (UnliftedArray (PrimArray a))

{-|
An immutable space-efficient sparse array, 
which can only store not more than 64 elements.
-}
data SparseSmallArray e = SparseSmallArray {-# UNPACK #-} !Bitmap {-# UNPACK #-} !(SmallArray e)

{-|
A word-size set of ints.
-}
newtype Bitmap = Bitmap Int64
