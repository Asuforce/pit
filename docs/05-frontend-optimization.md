# Phase 5: フロントエンド最適化

## 学習目標
- Core Web Vitalsの理解と改善
- Code Splittingとlazy loadingの実装
- 画像最適化戦略
- Next.jsでのパフォーマンス設定

## Core Web Vitals

### Largest Contentful Paint (LCP)
ページ読み込み後、最大の視認可能要素が描画されるまでの時間。

目標: 2.5秒以下

改善方法：
- 画像の最適化
- CSSの最小化
- JavaScriptの遅延読み込み
- フォントの最適化

### First Input Delay (FID)
ユーザーの最初のアクション（クリック等）に対する応答時間。

目標: 100ミリ秒以下

改善方法：
- JavaScriptの分割
- メインスレッドのブロッキング削減
- Web Workersの活用

### Cumulative Layout Shift (CLS)
レイアウトが予期しない変化する度合い。

目標: 0.1以下

改善方法：
- 画像サイズの指定
- 動的コンテンツの予約スペース確保
- フォントのpreload

## Next.js最適化設定

### next.config.js

```javascript
// next.config.js
module.exports = {
  // 画像最適化
  images: {
    formats: ['image/webp', 'image/avif'],
    deviceSizes: [640, 750, 828, 1080, 1200, 1920, 2048, 3840],
    imageSizes: [16, 32, 48, 64, 96, 128, 256, 384],
  },

  // SWCによるコンパイル（Babelより高速）
  swcMinify: true,

  // ゴルチリント API routes
  compress: true,

  // 生成時最適化
  generateEtags: true,

  // Poweredヘッダー削除
  poweredByHeader: false,
};
```

## Code Splitting

### ルートベース自動分割

```typescript
// pages/products/index.tsx
// 自動的に products.js に分割される
import ProductList from '@/components/ProductList';

export default function Products() {
  return <ProductList />;
}
```

### 動的importによる遅延読み込み

```typescript
import dynamic from 'next/dynamic';

const HeavyComponent = dynamic(() => import('@/components/HeavyComponent'), {
  loading: () => <p>Loading...</p>,
  ssr: false,
});

export default function Page() {
  return <HeavyComponent />;
}
```

### React.lazy活用

```typescript
import { lazy, Suspense } from 'react';

const ProductDetail = lazy(() => import('@/components/ProductDetail'));

export default function Page() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ProductDetail />
    </Suspense>
  );
}
```

## 画像最適化

### Next.js Image コンポーネント

```typescript
import Image from 'next/image';

export default function ProductCard({ product }) {
  return (
    <div>
      <Image
        src={product.imageUrl}
        alt={product.name}
        width={300}
        height={300}
        priority={false}  // ファーストビューのみtrueに
        loading="lazy"
      />
    </div>
  );
}
```

### 自動WebP変換

```typescript
<Image
  src="/products/img.jpg"
  alt="Product"
  width={400}
  height={400}
  // 自動的にWebP版が提供される
/>
```

### 画像サイズの事前指定（CLS対策）

```typescript
<Image
  src={productImage}
  alt="Product"
  width={300}
  height={300}
  // レイアウト シフトなし
/>
```

## フォント最適化

### next/fontの使用

```typescript
// lib/fonts.ts
import { Inter, Roboto } from 'next/font/google';

export const inter = Inter({
  subsets: ['latin'],
  preload: true,
  display: 'swap',
});

export const roboto = Roboto({
  weight: ['400', '700'],
  subsets: ['latin'],
  display: 'swap',
});

// _app.tsx
import { inter, roboto } from '@/lib/fonts';

function MyApp({ Component, pageProps }) {
  return (
    <div className={inter.className}>
      <Component {...pageProps} />
    </div>
  );
}
```

## React最適化パターン

### Memoization

```typescript
import { memo } from 'react';

const ProductCard = memo(function ProductCard({ product, onSelect }) {
  return (
    <div onClick={() => onSelect(product.id)}>
      {product.name}
    </div>
  );
});

export default ProductCard;
```

### useCallbackの活用

```typescript
import { useCallback } from 'react';

export default function ProductList() {
  const handleSelect = useCallback((productId) => {
    // 複雑な処理
    console.log(`Selected: ${productId}`);
  }, []);

  return (
    <div>
      {products.map(p => (
        <ProductCard key={p.id} product={p} onSelect={handleSelect} />
      ))}
    </div>
  );
}
```

### useMemoの活用

```typescript
import { useMemo } from 'react';

export default function ProductDetail({ product }) {
  const totalReviewRating = useMemo(() => {
    return product.reviews.reduce((sum, r) => sum + r.rating, 0) / product.reviews.length;
  }, [product.reviews]);

  return <div>Average Rating: {totalReviewRating}</div>;
}
```

## パフォーマンス計測

### Lighthouseで計測

```bash
# CLI版
npm install -g @google/chrome-headless-shell
npm install -g lighthouse

lighthouse https://localhost:3000 --view
```

### Web Vitals計測

```typescript
// lib/web-vitals.ts
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

export function reportWebVitals(metric) {
  console.log(metric);
}

// _app.tsx
import { reportWebVitals } from '@/lib/web-vitals';

export default reportWebVitals;
```

## 演習課題

### 課題1: Code Splitting確認
1. 商品詳細ページを動的importに変更
2. ネットワークタブでバンドルサイズを確認
3. メインバンドルから分割されることを確認

### 課題2: 画像最適化
1. 全ての商品画像をNext.js Imageに変更
2. widthとheightを指定
3. 画像サイズが自動最適化されることを確認

### 課題3: Core Web Vitals改善
1. Lighthouseで現在のスコアを計測
2. LCP/FID/CLSを確認
3. 各フェーズで改善

## チェックリスト

- [ ] Code Splittingが機能している
- [ ] next/imageが使用されている
- [ ] next/fontが設定されている
- [ ] Lighthouseスコアが記録されている
- [ ] Core Web Vitalsが計測されている

## パフォーマンス比較

| 指標 | 改善前 | 改善後 |
|------|------|------|
| バンドルサイズ | 450KB | 200KB |
| LCP | 3.5s | 2.0s |
| FID | 150ms | 80ms |
| CLS | 0.25 | 0.05 |
