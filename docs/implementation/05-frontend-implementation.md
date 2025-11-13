# Phase 5: フロントエンド最適化実装ガイド

## 概要

このフェーズでは、Next.js フロントエンドの最適化に取り組みます。Core Web Vitals（LCP、FID、CLS）を改善し、ユーザー体験を向上させます。バックエンド（Phase 1-4）が完成した後で、フロントエンドの実装を進めます。

**目標**:
- Core Web Vitals の理解と改善
- Next.js の最適化設定
- コード分割と動的インポート
- 画像最適化とフォント最適化
- React メモ化パターンの実装

---

## 前提条件

### 完了していることを確認
- Phase 1-4: バックエンド実装完了
- GraphQL エンドポイントが正常に動作

### 環境要件
- Node.js 18以上
- npm または yarn

### 技術的前提
- React の基礎知識
- Next.js の基本的な使用方法
- CSS-in-JS または CSS Modules の知識

---

## パート1: Core Web Vitals の理解

### 1.1 3つの重要指標

| 指標 | 説明 | 良好 | 要改善 |
|-----|------|------|--------|
| **LCP** | Largest Contentful Paint（最大のコンテンツ描画） | < 2.5s | > 4.0s |
| **FID** | First Input Delay（最初の入力遅延） | < 100ms | > 300ms |
| **CLS** | Cumulative Layout Shift（累積レイアウトシフト） | < 0.1 | > 0.25 |

### 1.2 LCP（Largest Contentful Paint）

最大の視認可能なコンテンツが描画されるまでの時間。

**改善方法**:
- 画像の遅延ロード
- 重いスクリプトの最適化
- サーバー応答時間の短縮

### 1.3 FID（First Input Delay）

ユーザーが最初にインタラクション（クリックなど）してから、ブラウザが応答するまでの時間。

**改善方法**:
- JavaScriptの実行時間短縮
- メインスレッドのブロッキングを減らす
- Web Workers の活用

### 1.4 CLS（Cumulative Layout Shift）

ページ読み込み中のレイアウトシフトの累積値。予期しないレイアウト変化はユーザー体験を損なう。

**改善方法**:
- 画像やメディアに幅と高さを指定
- フォントの読み込み時の FOUT/FOIT を回避
- コンテンツの挿入による shift を防止

---

## パート2: Next.js プロジェクトのセットアップ

### 2.1 Next.js プロジェクト生成

```bash
# プロジェクトルートで実行
npm create next-app@latest frontend -- \
  --typescript \
  --tailwind \
  --eslint \
  --app-dir

cd frontend
```

### 2.2 ディレクトリ構造

```
frontend/
├── app/
│   ├── layout.tsx          # ルートレイアウト
│   ├── page.tsx            # ホームページ
│   ├── products/
│   │   ├── page.tsx        # 商品リスト
│   │   └── [id]/
│   │       └── page.tsx    # 商品詳細
│   └── api/                # API ルート
├── components/
│   ├── ProductCard.tsx
│   ├── ProductList.tsx
│   └── ProductImage.tsx
├── lib/
│   ├── graphql-client.ts   # GraphQL クライアント
│   ├── web-vitals.ts       # Web Vitals 計測
│   └── hooks/
│       └── useProducts.ts
├── public/
│   └── images/
├── styles/
│   └── globals.css
├── next.config.js
├── tailwind.config.js
└── tsconfig.json
```

### 2.3 GraphQL クライアントの設定

`frontend/lib/graphql-client.ts`:

```typescript
import { GraphQLClient } from 'graphql-request';

const endpoint = process.env.NEXT_PUBLIC_GRAPHQL_ENDPOINT || 'http://localhost:3000/graphql';

export const graphqlClient = new GraphQLClient(endpoint, {
  headers: {
    'Content-Type': 'application/json',
  },
});

// キャッシュ付きで実行
export async function fetchGraphQL(query: string, variables?: Record<string, any>) {
  const cacheKey = `graphql:${query}:${JSON.stringify(variables)}`;

  // ブラウザキャッシュを確認
  if (typeof window !== 'undefined') {
    const cached = sessionStorage.getItem(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }
  }

  const result = await graphqlClient.request(query, variables);

  // 結果をキャッシュ
  if (typeof window !== 'undefined') {
    sessionStorage.setItem(cacheKey, JSON.stringify(result));
  }

  return result;
}
```

---

## パート3: Next.js 最適化設定

### 3.1 next.config.js の最適化

`frontend/next.config.js`:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // 画像最適化
  images: {
    remotePatterns: [
      {
        protocol: 'http',
        hostname: 'localhost',
        port: '3000',
      },
    ],
    // 次世代形式での配信
    formats: ['image/avif', 'image/webp'],
    // 画像のキャッシング
    minimumCacheTTL: 60 * 60 * 24 * 365, // 1 year
  },

  // JavaScript の圧縮（SWC 使用）
  swcMinify: true,

  // 本番環境での最適化
  compress: true,

  // ビルド出力の最適化
  poweredByHeader: false,

  // React strict mode（開発環境）
  reactStrictMode: true,

  // 国際化対応（オプション）
  i18n: {
    locales: ['en'],
    defaultLocale: 'en',
  },

  // キャッシュ戦略
  onDemandEntries: {
    maxInactiveAge: 60 * 1000,     // 60秒
    pagesBufferLength: 5,           // 5ページをメモリに保持
  },

  // 環境変数
  env: {
    NEXT_PUBLIC_GRAPHQL_ENDPOINT: process.env.NEXT_PUBLIC_GRAPHQL_ENDPOINT,
  },

  // トレーニングモード（本番では無効化）
  experimental: {
    optimizePackageImports: [
      'lodash-es',
      'date-fns',
    ],
  },
};

module.exports = nextConfig;
```

### 3.2 Root Layout の設定

`frontend/app/layout.tsx`:

```typescript
import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { WebVitals } from '@/lib/web-vitals';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',  // FOUT を回避
  preload: true,    // フォントを事前ロード
});

export const metadata: Metadata = {
  title: 'PIT - Performance Improving Training',
  description: 'Learn web performance optimization',
  openGraph: {
    title: 'PIT',
    description: 'Performance Improving Training',
    type: 'website',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.className}>
      <head>
        {/* フォント最適化 */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />

        {/* DNS Prefetch */}
        <link rel="dns-prefetch" href="http://localhost:3000" />

        {/* Preload LCP 画像 */}
        <link
          rel="preload"
          as="image"
          href="/images/hero.jpg"
          imagesrcset="/images/hero-320w.jpg 320w, /images/hero-640w.jpg 640w"
          imagesizes="(max-width: 640px) 320px, 640px"
        />
      </head>
      <body>
        <main>{children}</main>
        {process.env.NODE_ENV === 'production' && <WebVitals />}
      </body>
    </html>
  );
}
```

---

## パート4: 画像最適化

### 4.1 Next.js Image コンポーネント

`frontend/components/ProductImage.tsx`:

```typescript
'use client';

import Image from 'next/image';
import { useState } from 'react';

interface ProductImageProps {
  src: string;
  alt: string;
  title?: string;
}

export default function ProductImage({ src, alt, title }: ProductImageProps) {
  const [isLoading, setIsLoading] = useState(true);

  return (
    <div className="relative w-full h-64 bg-gray-100">
      <Image
        src={src}
        alt={alt}
        title={title}
        fill
        // 関連する画像最適化オプション
        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
        priority={false}  // LCP 画像の場合は priority={true}
        quality={80}      // JPEG 品質
        placeholder="blur" // 遅延ロード時の blur 効果
        blurDataURL="data:image/jpeg;base64,..."
        // 読み込み完了時のコールバック
        onLoadingComplete={() => setIsLoading(false)}
        // エラーハンドリング
        onError={() => console.error('Image failed to load')}
      />
      {isLoading && (
        <div className="absolute inset-0 bg-gray-200 animate-pulse" />
      )}
    </div>
  );
}
```

### 4.2 レスポンシブ画像

複数の画像サイズに対応：

`frontend/components/HeroImage.tsx`:

```typescript
'use client';

import Image from 'next/image';

export default function HeroImage() {
  return (
    <div className="relative w-full h-96">
      <Image
        src="/images/hero.jpg"
        alt="Hero image"
        fill
        // LCP 画像のため priority を有効化
        priority={true}
        quality={90}
        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 80vw, 100vw"
        // CSS-in-JS を使用する場合
        style={{
          objectFit: 'cover',
        }}
      />
    </div>
  );
}
```

---

## パート5: コード分割と動的インポート

### 5.1 Route ベースのコード分割

App Router では自動的にルートごとにコードが分割されます。

`frontend/app/products/page.tsx`:

```typescript
import ProductList from '@/components/ProductList';
import { Suspense } from 'react';

export default function ProductsPage() {
  return (
    <div>
      <h1>Products</h1>
      <Suspense fallback={<div>Loading products...</div>}>
        <ProductList />
      </Suspense>
    </div>
  );
}
```

### 5.2 動的インポート（Lazy Loading）

重い機能を遅延ロード：

`frontend/components/ProductList.tsx`:

```typescript
'use client';

import dynamic from 'next/dynamic';
import { useState } from 'react';

// 重い分析ツールを動的インポート
const ProductAnalytics = dynamic(() => import('./ProductAnalytics'), {
  loading: () => <p>Loading analytics...</p>,
  ssr: false, // SSR を無効化（ブラウザのみで実行）
});

// 重いチャートライブラリ
const ProductChart = dynamic(() => import('./ProductChart'), {
  loading: () => <div className="h-64 bg-gray-100" />,
  ssr: false,
});

export default function ProductList() {
  const [showAnalytics, setShowAnalytics] = useState(false);
  const [showChart, setShowChart] = useState(false);

  return (
    <div>
      <button onClick={() => setShowAnalytics(!showAnalytics)}>
        Show Analytics
      </button>
      {showAnalytics && <ProductAnalytics />}

      <button onClick={() => setShowChart(!showChart)}>
        Show Chart
      </button>
      {showChart && <ProductChart />}
    </div>
  );
}
```

### 5.3 モーダルの動的インポート

```typescript
'use client';

import dynamic from 'next/dynamic';
import { useState } from 'react';

const ProductModal = dynamic(() => import('./ProductModal'), {
  ssr: false,
});

export default function ProductCard() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      <button onClick={() => setIsOpen(true)}>Open Details</button>
      {isOpen && <ProductModal onClose={() => setIsOpen(false)} />}
    </>
  );
}
```

---

## パート6: React メモ化パターン

### 6.1 React.memo

不要な再レンダーを回避：

`frontend/components/ProductCard.tsx`:

```typescript
'use client';

import { memo } from 'react';
import ProductImage from './ProductImage';

interface ProductCardProps {
  id: number;
  name: string;
  price: number;
  imageUrl: string;
  onSelect?: (id: number) => void;
}

// 親が再レンダーされても、props が同じであれば再レンダーしない
const ProductCard = memo(function ProductCard({
  id,
  name,
  price,
  imageUrl,
  onSelect,
}: ProductCardProps) {
  return (
    <div className="border rounded-lg p-4">
      <ProductImage src={imageUrl} alt={name} />
      <h3 className="text-lg font-bold">{name}</h3>
      <p className="text-gray-600">${price.toFixed(2)}</p>
      {onSelect && (
        <button onClick={() => onSelect(id)}>
          View Details
        </button>
      )}
    </div>
  );
});

export default ProductCard;
```

### 6.2 useCallback

コールバック関数のメモ化：

```typescript
'use client';

import { useCallback, useState } from 'react';
import ProductCard from './ProductCard';

interface Product {
  id: number;
  name: string;
  price: number;
  imageUrl: string;
}

export default function ProductList({ products }: { products: Product[] }) {
  const [selectedId, setSelectedId] = useState<number | null>(null);

  // onSelect は products が変わっても同じ参照を保持
  const handleSelect = useCallback((id: number) => {
    setSelectedId(id);
  }, []);

  return (
    <div className="grid grid-cols-3 gap-4">
      {products.map((product) => (
        <ProductCard
          key={product.id}
          {...product}
          onSelect={handleSelect}
        />
      ))}
    </div>
  );
}
```

### 6.3 useMemo

計算結果のメモ化：

```typescript
'use client';

import { useMemo } from 'react';

interface Review {
  id: number;
  rating: number;
  comment: string;
}

interface ProductDetailProps {
  reviews: Review[];
}

export default function ProductDetail({ reviews }: ProductDetailProps) {
  // 計算結果をメモ化
  const averageRating = useMemo(() => {
    if (reviews.length === 0) return 0;
    const sum = reviews.reduce((acc, review) => acc + review.rating, 0);
    return (sum / reviews.length).toFixed(2);
  }, [reviews]);

  const positiveReviews = useMemo(
    () => reviews.filter((r) => r.rating >= 4),
    [reviews]
  );

  return (
    <div>
      <h2>Average Rating: {averageRating}</h2>
      <p>Positive Reviews: {positiveReviews.length}</p>
    </div>
  );
}
```

---

## パート7: Web Vitals の計測

### 7.1 Web Vitals ライブラリ

`frontend/lib/web-vitals.ts`:

```typescript
import { onCLS, onFID, onFCP, onLCP, onTTFB } from 'web-vitals';

const vitalsUrl = '/api/vitals';

function getConnectionSpeed() {
  if (
    typeof navigator !== 'undefined' &&
    navigator.connection &&
    'effectiveType' in navigator.connection
  ) {
    return (navigator.connection as any).effectiveType;
  }
  return '';
}

export function sendToAnalytics(metric: any) {
  const body = {
    ...metric,
    url: window.location.href,
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    connectionSpeed: getConnectionSpeed(),
  };

  // Use `navigator.sendBeacon()` if available, falling back to `fetch()`
  if (navigator.sendBeacon) {
    navigator.sendBeacon(vitalsUrl, JSON.stringify(body));
  } else {
    fetch(vitalsUrl, { body: JSON.stringify(body), method: 'POST', keepalive: true }).catch(
      (err) => {
        console.error(err);
      }
    );
  }
}

export function WebVitals() {
  // ブラウザ環境でのみ実行
  if (typeof window !== 'undefined') {
    onTTFB(sendToAnalytics);
    onFCP(sendToAnalytics);
    onLCP(sendToAnalytics);
    onCLS(sendToAnalytics);
    onFID(sendToAnalytics);
  }

  return null;
}
```

### 7.2 API ルートでメトリクスを記録

`frontend/app/api/vitals/route.ts`:

```typescript
import { NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    console.log('Web Vitals:', {
      name: body.name,
      value: body.value,
      url: body.url,
      connectionSpeed: body.connectionSpeed,
      timestamp: new Date().toISOString(),
    });

    // データベースに記録する場合
    // await saveVitalToDatabase(body);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error recording vitals:', error);
    return NextResponse.json(
      { error: 'Failed to record vitals' },
      { status: 500 }
    );
  }
}
```

---

## パート8: パフォーマンス計測と最適化

### 8.1 Lighthouse での計測

```bash
# npm 経由で実行
npm install -g lighthouse

# PageSpeed Insights CLI
lighthouse http://localhost:3000 --view

# JSON 出力
lighthouse http://localhost:3000 --output=json > lighthouse.json
```

### 8.2 メトリクス記録

```json
{
  "phase": 5,
  "timestamp": "2024-01-15T14:00:00Z",
  "metrics": {
    "lighthouse": {
      "performance": 85,
      "accessibility": 90,
      "best_practices": 92,
      "seo": 95
    },
    "core_web_vitals": {
      "lcp_ms": 1800,
      "fid_ms": 60,
      "cls": 0.08
    },
    "bundle_size": {
      "total_kb": 150,
      "javascript_kb": 85,
      "css_kb": 25
    }
  }
}
```

---

## 関連ドキュメント

- **学習ガイド**: [../05-frontend-optimization.md](../05-frontend-optimization.md) - フロントエンド最適化の理論
- **前の実装**: [04-graphql-implementation.md](./04-graphql-implementation.md) - Phase 4: GraphQL最適化
- **次の実装**: [06-database-implementation.md](./06-database-implementation.md) - Phase 6: DB最適化

---

## 実装チェックリスト

- [ ] Next.js プロジェクトが初期化
- [ ] GraphQL クライアントが設定
- [ ] next.config.js が最適化
- [ ] 画像最適化が実装
- [ ] コード分割が機能
- [ ] React.memo が適用
- [ ] useCallback が実装
- [ ] useMemo が実装
- [ ] Web Vitals が計測
- [ ] Lighthouse スコアが 85以上

---

## 次のステップ

Phase 5が完了したら、[Phase 6: データベース最適化実装ガイド](./06-database-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ Next.js が最適化設定済み
- ✅ 画像最適化が実装
- ✅ コード分割が機能
- ✅ React メモ化パターンが実装
- ✅ Core Web Vitals を計測
- ✅ Lighthouse スコア向上

次のフェーズでは、MySQL インデックス設計とクエリ最適化を学びます。
