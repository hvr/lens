{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeOperators #-}

#ifdef TRUSTWORTHY
{-# LANGUAGE Trustworthy #-}
#endif

#ifndef MIN_VERSION_base
#define MIN_VERSION_base(x,y,z) 1
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.At
-- Copyright   :  (C) 2012-14 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
--
----------------------------------------------------------------------------
module Control.Lens.At
  (
  -- * At
    At(at), sans
  -- * Ixed
  , Index
  , IxValue
  , Ixed(ix)
  , ixAt
  -- * Contains
  , Contains(..)
  ) where

import Control.Applicative
import Control.Lens.Lens
import Control.Lens.Setter
import Control.Lens.Type
import Control.Lens.Internal.TupleIxedTH (makeAllTupleIxed)
import Data.Aeson as Aeson
import Data.Array.IArray as Array
import Data.Array.Unboxed
import Data.ByteString as StrictB
import Data.ByteString.Lazy as LazyB
import Data.Complex
import Data.Hashable
import Data.HashMap.Lazy as HashMap
import Data.HashSet as HashSet
import Data.Int
import Data.IntMap as IntMap
import Data.IntSet as IntSet
import Data.List.NonEmpty as NonEmpty
import Data.Map as Map
import Data.Set as Set
import Data.Sequence as Seq
import Data.Text as StrictT
import Data.Text.Lazy as LazyT
import Data.Traversable
import Data.Tree
import Data.Vector as Vector hiding (indexed)
import Data.Vector.Primitive as Prim
import Data.Vector.Storable as Storable
import Data.Vector.Unboxed as Unboxed
import Data.Word

type family Index (s :: *) :: *
type instance Index (e -> a) = e
type instance Index IntSet = Int
type instance Index (Set a) = a
type instance Index (HashSet a) = a
type instance Index [a] = Int
type instance Index (NonEmpty a) = Int
type instance Index (Seq a) = Int
type instance Index (a,b) = Int
type instance Index (a,b,c) = Int
type instance Index (a,b,c,d) = Int
type instance Index (a,b,c,d,e) = Int
type instance Index (a,b,c,d,e,f) = Int
type instance Index (a,b,c,d,e,f,g) = Int
type instance Index (a,b,c,d,e,f,g,h) = Int
type instance Index (a,b,c,d,e,f,g,h,i) = Int
type instance Index (IntMap a) = Int
type instance Index (Map k a) = k
type instance Index (HashMap k a) = k
type instance Index (Array.Array i e) = i
type instance Index (UArray i e) = i
type instance Index (Vector.Vector a) = Int
type instance Index (Prim.Vector a) = Int
type instance Index (Storable.Vector a) = Int
type instance Index (Unboxed.Vector a) = Int
type instance Index (Complex a) = Int
type instance Index (Identity a) = ()
type instance Index (Maybe a) = ()
type instance Index (Tree a) = [Int]
type instance Index StrictT.Text = Int
type instance Index LazyT.Text = Int64
type instance Index StrictB.ByteString = Int
type instance Index LazyB.ByteString = Int64
type instance Index Aeson.Value = StrictT.Text

-- $setup
-- >>> :set -XNoOverloadedStrings
-- >>> import Control.Lens
-- >>> import Debug.SimpleReflect.Expr
-- >>> import Debug.SimpleReflect.Vars as Vars hiding (f,g)
-- >>> let f :: Expr -> Expr; f = Debug.SimpleReflect.Vars.f
-- >>> let g :: Expr -> Expr; g = Debug.SimpleReflect.Vars.g

-- |
-- This class provides a simple 'IndexedFold' (or 'IndexedTraversal') that lets you view (and modify)
-- information about whether or not a container contains a given 'Index'.
class Contains m where
  -- |
  -- >>> IntSet.fromList [1,2,3,4] ^. contains 3
  -- True
  --
  -- >>> IntSet.fromList [1,2,3,4] ^. contains 5
  -- False
  --
  -- >>> IntSet.fromList [1,2,3,4] & contains 3 .~ False
  -- fromList [1,2,4]
  contains :: Index m -> Lens' m Bool

instance Contains IntSet where
  contains k f s = f (IntSet.member k s) <&> \b ->
    if b then IntSet.insert k s else IntSet.delete k s
  {-# INLINE contains #-}

instance Ord a => Contains (Set a) where
  contains k f s = f (Set.member k s) <&> \b ->
    if b then Set.insert k s else Set.delete k s
  {-# INLINE contains #-}

instance (Eq a, Hashable a) => Contains (HashSet a) where
  contains k f s = f (HashSet.member k s) <&> \b ->
    if b then HashSet.insert k s else HashSet.delete k s
  {-# INLINE contains #-}

-- | This provides a common notion of a value at an index that is shared by both 'Ixed' and 'At'.
type family IxValue (m :: *) :: *

-- | This simple 'AffineTraversal' lets you 'traverse' the value at a given
-- key in a 'Map' or element at an ordinal position in a list or 'Seq'.
class Ixed m where
  -- | This simple 'AffineTraversal' lets you 'traverse' the value at a given
  -- key in a 'Map' or element at an ordinal position in a list or 'Seq'.
  --
  -- /NB:/ Setting the value of this 'AffineTraversal' will only set the value in the
  -- 'Lens' if it is already present.
  --
  -- If you want to be able to insert /missing/ values, you want 'at'.
  --
  -- >>> Seq.fromList [a,b,c,d] & ix 2 %~ f
  -- fromList [a,b,f c,d]
  --
  -- >>> Seq.fromList [a,b,c,d] & ix 2 .~ e
  -- fromList [a,b,e,d]
  --
  -- >>> Seq.fromList [a,b,c,d] ^? ix 2
  -- Just c
  --
  -- >>> Seq.fromList [] ^? ix 2
  -- Nothing
  ix :: Index m -> Traversal' m (IxValue m)
#ifdef DEFAULT_SIGNATURES
  default ix :: (Applicative f, At m) => Index m -> LensLike' f m (IxValue m)
  ix = ixAt
  {-# INLINE ix #-}
#endif

-- | A definition of 'ix' for types with an 'At' instance. This is the default
-- if you don't specify a definition for 'ix'.
ixAt :: At m => Index m -> Traversal' m (IxValue m)
ixAt i = at i . traverse
{-# INLINE ixAt #-}

type instance IxValue (e -> a) = a
instance Eq e => Ixed (e -> a) where
  ix e p f = p (f e) <&> \a e' -> if e == e' then a else f e'
  {-# INLINE ix #-}

type instance IxValue (Maybe a) = a
instance Ixed (Maybe a) where
  ix () f (Just a) = Just <$> f a
  ix () _ Nothing  = pure Nothing
  {-# INLINE ix #-}

type instance IxValue [a] = a
instance Ixed [a] where
  ix k f xs0 | k < 0     = pure xs0
             | otherwise = go xs0 k where
    go [] _ = pure []
    go (a:as) 0 = f a <&> (:as)
    go (a:as) i = (a:) <$> (go as $! i - 1)
  {-# INLINE ix #-}

type instance IxValue (NonEmpty a) = a
instance Ixed (NonEmpty a) where
  ix k f xs0 | k < 0 = pure xs0
             | otherwise = go xs0 k where
    go (a:|as) 0 = f a <&> (:|as)
    go (a:|as) i = (a:|) <$> ix (i - 1) f as
  {-# INLINE ix #-}

type instance IxValue (Identity a) = a
instance Ixed (Identity a) where
  ix () f (Identity a) = Identity <$> f a
  {-# INLINE ix #-}

type instance IxValue (Tree a) = a
instance Ixed (Tree a) where
  ix xs0 f = go xs0 where
    go [] (Node a as) = f a <&> \a' -> Node a' as
    go (i:is) t@(Node a as) | i < 0     = pure t
                            | otherwise = Node a <$> goto is as i
    goto is (a:as) 0 = go is a <&> (:as)
    goto is (_:as) n = goto is as $! n - 1
    goto _  []     _ = pure []
  {-# INLINE ix #-}

type instance IxValue (Seq a) = a
instance Ixed (Seq a) where
  ix i f m
    | 0 <= i && i < Seq.length m = f (Seq.index m i) <&> \a -> Seq.update i a m
    | otherwise                  = pure m
  {-# INLINE ix #-}

type instance IxValue (IntMap a) = a
instance Ixed (IntMap a) where
  ix k f m = case IntMap.lookup k m of
     Just v -> f v <&> \v' -> IntMap.insert k v' m
     Nothing -> pure m
  {-# INLINE ix #-}

type instance IxValue (Map k a) = a
instance Ord k => Ixed (Map k a) where
  ix k f m = case Map.lookup k m of
     Just v  -> f v <&> \v' -> Map.insert k v' m
     Nothing -> pure m
  {-# INLINE ix #-}

type instance IxValue (HashMap k a) = a
instance (Eq k, Hashable k) => Ixed (HashMap k a) where
  ix k f m = case HashMap.lookup k m of
     Just v  -> f v <&> \v' -> HashMap.insert k v' m
     Nothing -> pure m
  {-# INLINE ix #-}

type instance IxValue (Set k) = ()
instance Ord k => Ixed (Set k) where
  ix k f m = if Set.member k m
     then f () <&> \() -> Set.insert k m
     else pure m
  {-# INLINE ix #-}

type instance IxValue IntSet = ()
instance Ixed IntSet where
  ix k f m = if IntSet.member k m
     then f () <&> \() -> IntSet.insert k m
     else pure m
  {-# INLINE ix #-}

type instance IxValue (HashSet k) = ()
instance (Eq k, Hashable k) => Ixed (HashSet k) where
  ix k f m = if HashSet.member k m
     then f () <&> \() -> HashSet.insert k m
     else pure m
  {-# INLINE ix #-}

type instance IxValue (Array.Array i e) = e
-- |
-- @
-- arr '!' i ≡ arr 'Control.Lens.Getter.^.' 'ix' i
-- arr '//' [(i,e)] ≡ 'ix' i 'Control.Lens.Setter..~' e '$' arr
-- @
instance Ix i => Ixed (Array.Array i e) where
  ix i f arr
    | inRange (bounds arr) i = f (arr Array.! i) <&> \e -> arr Array.// [(i,e)]
    | otherwise              = pure arr
  {-# INLINE ix #-}

type instance IxValue (UArray i e) = e
-- |
-- @
-- arr '!' i ≡ arr 'Control.Lens.Getter.^.' 'ix' i
-- arr '//' [(i,e)] ≡ 'ix' i 'Control.Lens.Setter..~' e '$' arr
-- @
instance (IArray UArray e, Ix i) => Ixed (UArray i e) where
  ix i f arr
    | inRange (bounds arr) i = f (arr Array.! i) <&> \e -> arr Array.// [(i,e)]
    | otherwise              = pure arr
  {-# INLINE ix #-}

type instance IxValue (Vector.Vector a) = a
instance Ixed (Vector.Vector a) where
  ix i f v
    | 0 <= i && i < Vector.length v = f (v Vector.! i) <&> \a -> v Vector.// [(i, a)]
    | otherwise                     = pure v
  {-# INLINE ix #-}

type instance IxValue (Prim.Vector a) = a
instance Prim a => Ixed (Prim.Vector a) where
  ix i f v
    | 0 <= i && i < Prim.length v = f (v Prim.! i) <&> \a -> v Prim.// [(i, a)]
    | otherwise                   = pure v
  {-# INLINE ix #-}

type instance IxValue (Storable.Vector a) = a
instance Storable a => Ixed (Storable.Vector a) where
  ix i f v
    | 0 <= i && i < Storable.length v = f (v Storable.! i) <&> \a -> v Storable.// [(i, a)]
    | otherwise                       = pure v
  {-# INLINE ix #-}

type instance IxValue (Unboxed.Vector a) = a
instance Unbox a => Ixed (Unboxed.Vector a) where
  ix i f v
    | 0 <= i && i < Unboxed.length v = f (v Unboxed.! i) <&> \a -> v Unboxed.// [(i, a)]
    | otherwise                      = pure v
  {-# INLINE ix #-}

type instance IxValue StrictT.Text = Char
instance Ixed StrictT.Text where
  ix e f s = case StrictT.splitAt e s of
     (l, mr) -> case StrictT.uncons mr of
       Nothing      -> pure s
       Just (c, xs) -> f c <&> \d -> StrictT.concat [l, StrictT.singleton d, xs]
  {-# INLINE ix #-}

type instance IxValue LazyT.Text = Char
instance Ixed LazyT.Text where
  ix e f s = case LazyT.splitAt e s of
     (l, mr) -> case LazyT.uncons mr of
       Nothing      -> pure s
       Just (c, xs) -> f c <&> \d -> LazyT.append l (LazyT.cons d xs)
  {-# INLINE ix #-}

type instance IxValue StrictB.ByteString = Word8
instance Ixed StrictB.ByteString where
  ix e f s = case StrictB.splitAt e s of
     (l, mr) -> case StrictB.uncons mr of
       Nothing      -> pure s
       Just (c, xs) -> f c <&> \d -> StrictB.concat [l, StrictB.singleton d, xs]
  {-# INLINE ix #-}

type instance IxValue LazyB.ByteString = Word8
instance Ixed LazyB.ByteString where
  -- TODO: we could be lazier, returning each chunk as it is passed
  ix e f s = case LazyB.splitAt e s of
     (l, mr) -> case LazyB.uncons mr of
       Nothing      -> pure s
       Just (c, xs) -> f c <&> \d -> LazyB.append l (LazyB.cons d xs)
  {-# INLINE ix #-}


type instance IxValue Aeson.Value = Aeson.Value
instance Ixed Aeson.Value where
  ix i f (Object o) = Object <$> ix i f o
  ix _ _ v          = pure v
  {-# INLINE ix #-}



-- | 'At' provides a 'Lens' that can be used to read,
-- write or delete the value associated with a key in a 'Map'-like
-- container on an ad hoc basis.
--
-- An instance of 'At' should satisfy:
--
-- @
-- 'ix' k ≡ 'at' k '.' 'traverse'
-- @
class Ixed m => At m where
  -- |
  -- >>> Map.fromList [(1,"world")] ^.at 1
  -- Just "world"
  --
  -- >>> at 1 ?~ "hello" $ Map.empty
  -- fromList [(1,"hello")]
  --
  -- /Note:/ 'Map'-like containers form a reasonable instance, but not 'Array'-like ones, where
  -- you cannot satisfy the 'Lens' laws.
  at :: Index m -> Lens' m (Maybe (IxValue m))

sans :: At m => Index m -> m -> m
sans k m = m & at k .~ Nothing
{-# INLINE sans #-}

instance At (Maybe a) where
  at () f = f
  {-# INLINE at #-}

instance At (IntMap a) where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (IntMap.delete k m)) mv
    Just v' -> IntMap.insert k v' m
    where mv = IntMap.lookup k m
  {-# INLINE at #-}

instance Ord k => At (Map k a) where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (Map.delete k m)) mv
    Just v' -> Map.insert k v' m
    where mv = Map.lookup k m
  {-# INLINE at #-}

instance (Eq k, Hashable k) => At (HashMap k a) where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (HashMap.delete k m)) mv
    Just v' -> HashMap.insert k v' m
    where mv = HashMap.lookup k m
  {-# INLINE at #-}

instance At IntSet where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (IntSet.delete k m)) mv
    Just () -> IntSet.insert k m
    where mv = if IntSet.member k m then Just () else Nothing
  {-# INLINE at #-}

instance Ord k => At (Set k) where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (Set.delete k m)) mv
    Just () -> Set.insert k m
    where mv = if Set.member k m then Just () else Nothing
  {-# INLINE at #-}

instance (Eq k, Hashable k) => At (HashSet k) where
  at k f m = f mv <&> \r -> case r of
    Nothing -> maybe m (const (HashSet.delete k m)) mv
    Just () -> HashSet.insert k m
    where mv = if HashSet.member k m then Just () else Nothing
  {-# INLINE at #-}

makeAllTupleIxed
