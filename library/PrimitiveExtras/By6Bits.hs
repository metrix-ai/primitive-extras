module PrimitiveExtras.By6Bits
(
  By6Bits,
  empty,
  singleton,
  maybeList,
  pair,
  insert,
  replace,
  adjust,
  revision,
  unset,
  lookup,
  focusAt,
  toMaybeList,
  toIndexedList,
  elementsUnfoldl,
  elementsUnfoldlM,
  elementsListT,
  onElementAtFocus,
  null,
)
where

import PrimitiveExtras.Prelude hiding (lookup, empty, insert, null)
import PrimitiveExtras.Types
import qualified PrimitiveExtras.Prelude as Prelude
import qualified PrimitiveExtras.Bitmap as Bitmap
import qualified PrimitiveExtras.SmallArray as SmallArray
import qualified Focus
import qualified Control.Foldl as Foldl


instance Show a => Show (By6Bits a) where
  show = show . toMaybeList

deriving instance Eq a => Eq (By6Bits a)

instance Foldable By6Bits where
  {-# INLINE foldr #-}
  foldr step state = foldr step state . elementsUnfoldl
  {-# INLINE foldl' #-}
  foldl' step state = foldl' step state . elementsUnfoldl
  {-# INLINE foldMap #-}
  foldMap monoid = foldMap monoid . elementsUnfoldl

{-# INLINE empty #-}
empty :: By6Bits e
empty = By6Bits Bitmap.empty Prelude.empty

-- |
-- An array with a single element at the specified index.
{-# INLINE singleton #-}
singleton :: Int -> e -> By6Bits e
singleton i e = 
  let b = Bitmap.singleton i
      a = runST $ newSmallArray 1 e >>= unsafeFreezeSmallArray
      in By6Bits b a

{-# INLINE pair #-}
pair :: Int -> e -> Int -> e -> By6Bits e
pair i1 e1 i2 e2 =
  {-# SCC "pair" #-} 
  By6Bits bitmap array
  where 
    bitmap = Bitmap.pair i1 i2
    array = SmallArray.orderedPair i1 e1 i2 e2

{-# INLINE maybeList #-}
maybeList :: [Maybe e] -> By6Bits e
maybeList list =
  By6Bits (Bitmap.boolList (map isJust list)) (SmallArray.list (catMaybes list))

{-|
Insert an element value at the index.
It's your obligation to ensure that the index is empty before the operation.
-}
{-# INLINE insert #-}
insert :: Int -> e -> By6Bits e -> By6Bits e
insert i e (By6Bits b a) =
  {-# SCC "insert" #-} 
  let
    sparseIndex = Bitmap.populatedIndex i b
    in By6Bits (Bitmap.insert i b) (SmallArray.insert sparseIndex e a)
    
{-# INLINE replace #-}
replace :: Int -> e -> By6Bits e -> By6Bits e
replace i e (By6Bits b a) =
  {-# SCC "replace" #-} 
  let
    sparseIndex = Bitmap.populatedIndex i b
    in By6Bits b (SmallArray.set sparseIndex e a)

{-# INLINE adjust #-}
adjust :: (e -> e) -> Int -> By6Bits e -> By6Bits e
adjust fn i (By6Bits b a) =
  let
    sparseIndex = Bitmap.populatedIndex i b
    in
      By6Bits b
        (SmallArray.unsafeAdjust fn sparseIndex a)

{-|
Very much like @alterF@ of the \"containers\" package
with two differences:

- For better performance @(Maybe e -> f (Maybe e))@ is replaced with
  the following two continuations: @f (Maybe e)@ and @(e -> f (Maybe e))@.
- The result is packed in @Maybe@ to inform you whether the map
  has become empty.
  This is useful for working with tries, since it can be used as
  a single to remove from a wrapping container.
-}
{-# INLINE revision #-}
revision :: Functor f => f (Maybe e) -> (e -> f (Maybe e)) -> Int -> By6Bits e -> f (Maybe (By6Bits e))
revision onMissing onPresent key (By6Bits (Bitmap bitmap) array) =
  let
    bitAtIndex = bit key
    isPopulated = bitmap .&. bitAtIndex /= 0
    populatedIndex = popCount (bitmap .&. pred bitAtIndex)
    in if isPopulated
      then let
        element = indexSmallArray array populatedIndex
        in
          onPresent element
            & fmap (\case
                Just newElement -> let
                  newArray = SmallArray.set populatedIndex newElement array
                  in Just (By6Bits (Bitmap bitmap) newArray)
                Nothing -> let
                  newBitmap = xor bitmap bitAtIndex
                  newArray = SmallArray.unset populatedIndex array
                  in if newBitmap == 0
                    then Nothing
                    else Just (By6Bits (Bitmap newBitmap) newArray))
      else
        onMissing & fmap (\case
          Just newElement -> let
            newArray = SmallArray.insert populatedIndex newElement array
            newBitmap = bitmap .|. bitAtIndex
            in Just (By6Bits (Bitmap newBitmap) newArray)
          Nothing -> if bitmap == 0
            then Nothing
            else Just (By6Bits (Bitmap bitmap) array))

-- |
-- Remove an element.
{-# INLINE unset #-}
unset :: Int -> By6Bits e -> By6Bits e
unset i (By6Bits (Bitmap b) a) =
  {-# SCC "unset" #-}
  let
    bitAtIndex = bit i
    isPopulated = b .&. bitAtIndex /= 0
    in if isPopulated
      then let
        populatedIndex = popCount (b .&. pred bitAtIndex)
        updatedBitmap = xor b bitAtIndex
        updatedArray = SmallArray.unset populatedIndex a
        in By6Bits (Bitmap updatedBitmap) updatedArray
      else By6Bits (Bitmap b) a

-- |
-- Lookup an item at the index.
{-# INLINE lookup #-}
lookup :: Int -> By6Bits e -> Maybe e
lookup i (By6Bits b a) =
  {-# SCC "lookup" #-} 
  if Bitmap.isPopulated i b
    then Just (indexSmallArray a (Bitmap.populatedIndex i b))
    else Nothing

-- |
-- Convert into a list representation.
{-# INLINE toMaybeList #-}
toMaybeList :: By6Bits e -> [Maybe e]
toMaybeList ssa = do
  i <- Bitmap.allBitsList
  return (lookup i ssa)

{-# INLINE toIndexedList #-}
toIndexedList :: By6Bits e -> [(Int, e)]
toIndexedList = catMaybes . zipWith (\i -> fmap (i,)) [0..] . toMaybeList

{-# INLINE elementsUnfoldl #-}
elementsUnfoldl :: By6Bits e -> Unfoldl e
elementsUnfoldl (By6Bits _ array) = Unfoldl (\ f z -> foldl' f z array)

{-# INLINE elementsUnfoldlM #-}
elementsUnfoldlM :: Monad m => By6Bits a -> UnfoldlM m a
elementsUnfoldlM (By6Bits _ array) = SmallArray.elementsUnfoldlM array

{-# INLINE elementsListT #-}
elementsListT :: By6Bits a -> ListT STM a
elementsListT (By6Bits _ array) = SmallArray.elementsListT array

{-# INLINE onElementAtFocus #-}
onElementAtFocus :: Monad m => Int -> Focus a m b -> Focus (By6Bits a) m b
onElementAtFocus index (Focus concealA revealA) = Focus concealSsa revealSsa where
  concealSsa = fmap (fmap aChangeToSsaChange) concealA where
    aChangeToSsaChange = \ case
      Focus.Leave -> Focus.Leave
      Focus.Set a -> Focus.Set (By6Bits (Bitmap.singleton index) (pure a))
      Focus.Remove -> Focus.Leave
  revealSsa (By6Bits indices array) =
    fmap (fmap aChangeToSsaChange) $
    if Bitmap.isPopulated index indices 
      then do
        a <- indexSmallArrayM array (Bitmap.populatedIndex index indices)
        revealA a
      else concealA
    where
      sparseIndex = Bitmap.populatedIndex index indices
      aChangeToSsaChange = \ case
        Focus.Leave -> Focus.Leave
        Focus.Set a -> if Bitmap.isPopulated index indices
          then let
            newArray = SmallArray.set sparseIndex a array
            in Focus.Set (By6Bits indices newArray)
          else let
            newIndices = Bitmap.insert index indices
            newArray = SmallArray.insert sparseIndex a array
            in Focus.Set (By6Bits newIndices newArray)
        Focus.Remove -> let
          newIndices = Bitmap.invert index indices
          in if Bitmap.null newIndices
            then Focus.Remove
            else let
              newArray = SmallArray.unset sparseIndex array
              in Focus.Set (By6Bits newIndices newArray)

{-# INLINE focusAt #-}
focusAt :: Monad m => Focus a m b -> Int -> By6Bits a -> m (b, By6Bits a)
focusAt aFocus index = case onElementAtFocus index aFocus of
  Focus conceal reveal -> \ ssa -> do
    (b, change) <- reveal ssa
    return $ (b,) $ case change of
      Focus.Leave -> ssa
      Focus.Set newSsa -> newSsa
      Focus.Remove -> empty

{-# INLINE null #-}
null :: By6Bits a -> Bool
null (By6Bits bm _) = Bitmap.null bm
