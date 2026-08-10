# Урок 26. Vite, структура проекта

Инструментальный урок. Как устроена сборка, как организовать код, чтобы через полгода в нём можно было разобраться.

---

# Часть 1. Теория

## 26.1 Что делает бандлер

Браузер умеет ESM нативно, но грузить тысячу модулей по одному — тысяча запросов. Плюс: TypeScript браузер не понимает, JSX тоже, зависимости лежат в `node_modules` с путями вида `import React from 'react'`, которые в браузере не разрешаются.

Бандлер решает: транспиляция TS/JSX, разрешение путей, сборка в минимум файлов, минификация, хеши в именах для кеширования.

**Vite делает это двумя разными способами.**

**В разработке** бандла нет вообще. Vite поднимает сервер, отдаёт модули по одному через нативный ESM, транспилируя на лету через esbuild. Отсюда мгновенный старт независимо от размера проекта — обрабатывается только то, что реально запрошено.

**В продакшене** сборка через Rollup: полный бандл, tree-shaking, разделение на чанки, оптимизация.

Двойственность иногда вылезает: код может работать в dev и падать в build. Поэтому `npm run build && npm run preview` перед деплоем — обязательная проверка.

**HMR** (hot module replacement) — замена модуля без перезагрузки страницы. Состояние React сохраняется, потому что плагин `@vitejs/plugin-react` умеет обновлять компоненты, не размонтируя их. Ломается, если в файле экспортируется не только компонент — тогда Vite перезагружает страницу целиком.

## 26.2 Конфигурация

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true },
      '/ws': { target: 'ws://localhost:8000', ws: true },
    },
  },
  build: {
    sourcemap: true,
    target: 'es2022',
  },
});
```

**Алиасы** убирают `../../../`:
```ts
import { Button } from '@/ui/Button';
```
Дублируются в `tsconfig.json`, иначе TypeScript не найдёт:
```json
{ "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["./src/*"] } } }
```

**Прокси** решает проблему CORS в разработке: фронт на 5173, бэкенд на 8000, запросы на `/api` уходят на бэкенд от имени того же origin. Для WebSocket — флаг `ws: true`.

## 26.3 Переменные окружения

```
# .env
VITE_API_URL=http://localhost:8000
VITE_MAX_FFT=8192
```

```ts
import.meta.env.VITE_API_URL;      // доступно в коде
import.meta.env.DEV;               // true в разработке
import.meta.env.PROD;
```

**Только префикс `VITE_` попадает в бандл.** Остальные Vite вырезает — защита от случайной утечки секретов на клиент.

**Всё, что попало в бандл, публично.** Не клади туда ключи API, токены, пароли. Кажется очевидным, но это регулярно происходит.

Типизация:
```ts
// src/vite-env.d.ts
interface ImportMetaEnv {
  readonly VITE_API_URL: string;
  readonly VITE_MAX_FFT: string;
}
interface ImportMeta { readonly env: ImportMetaEnv }
```
Теперь опечатка в имени переменной не скомпилируется.

## 26.4 Структура проекта

Два подхода.

**По типу файлов** — работает до примерно 30 компонентов:
```
src/
  components/
  hooks/
  lib/
  types.ts
```
Дальше `components/` превращается в свалку из ста файлов без связи между собой.

**По фичам** — масштабируется:
```
src/
  app/                    # сборка приложения
    App.tsx
    routes.tsx
  features/
    analysis/             # всё про анализ в одном месте
      components/
      hooks/
      state/
      types.ts
      index.ts            # публичный интерфейс фичи
    runs/
    settings/
  ui/                     # примитивы без доменного знания
    Button.tsx
    Field.tsx
    Panel.tsx
  lib/                    # утилиты без React
    dsp.ts
    objects.ts
  types.ts                # общие типы
```

**Правила, которые делают эту схему рабочей:**

1. **Фичи не импортируют друг у друга напрямую** — только через `index.ts`. Это позволяет менять внутренности, не ломая соседей
2. **`ui/` не знает о домене** — `Button` не должен импортировать `types.ts` с FFT
3. **`lib/` не знает о React** — чистые функции, тестируются без окружения
4. **Зависимости направлены внутрь**: `app` → `features` → `ui`/`lib`. Обратных стрелок нет

Четвёртое правило — самое важное. Если `ui/Button` начал импортировать что-то из `features/analysis`, слои перепутались, и переиспользовать `Button` уже нельзя.

**Правило одного файла:** пока фича маленькая, держи её в одном файле. Разбивай, когда файл перестал помещаться в голове, а не заранее.

## 26.5 Разделение кода

Тяжёлые части грузятся по требованию:

```tsx
import { lazy, Suspense } from 'react';

const SpectrumView = lazy(() => import('@/features/analysis/SpectrumView'));

<Suspense fallback={<Spinner />}>
  <SpectrumView bins={bins} />
</Suspense>
```

Vite создаст отдельный чанк, который загрузится при первом рендере компонента.

**Что стоит выносить:** страницы, редко используемые модалки, тяжёлые библиотеки (графики, редакторы), панели администратора.

**Что не стоит:** мелкие компоненты — выигрыш меньше накладных расходов на отдельный запрос.

`lazy` требует **default-экспорт**. Если у компонента именованный:
```tsx
const View = lazy(() => import('./View').then(m => ({ default: m.View })));
```

## 26.6 Web Worker

Для тебя это самая практичная часть урока. Vite поддерживает воркеры нативно:

```ts
// src/lib/fft.worker.ts
import type { FftConfig } from '@/types';

type Request = { samples: Float32Array; config: FftConfig };
type Response = { bins: Float32Array };

self.onmessage = (e: MessageEvent<Request>) => {
  const bins = computeFft(e.data.samples, e.data.config);
  // передаём владение буфером, а не копируем
  (self as unknown as Worker).postMessage({ bins }, [bins.buffer]);
};
```

```ts
// использование
const worker = new Worker(
  new URL('./fft.worker.ts', import.meta.url),
  { type: 'module' }
);
```

Синтаксис `new URL(..., import.meta.url)` обязателен — по нему Vite находит файл и собирает его отдельно.

**Transferable objects** — второй аргумент `postMessage`. Буфер передаётся по ссылке, копирования нет. Для мегабайтных массивов разница принципиальная. После передачи буфер в исходном контексте становится пустым — владение перешло.

Это ответ на урок 01: тяжёлые вычисления не в главном потоке. Воркер — настоящий поток ОС, главный поток остаётся отзывчивым.

## 26.7 Скрипты

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src --max-warnings 0",
    "test": "vitest"
  }
}
```

**`tsc --noEmit` в `build`** — критично. Повторю из урока 12: **Vite не проверяет типы**, esbuild их просто вырезает. Без явного вызова `tsc` сборка пройдёт с любыми ошибками типов.

**`--max-warnings 0`** — предупреждения линтера накапливаются и перестают читаться. Либо чинить, либо отключать правило осознанно.

---

# Часть 2. Проработка

## Задача. Реорганизация проекта

Приводим `dsp-panel` к структуре, которая выдержит блок 5.

```
src/
  app/
    App.tsx
    main.tsx
  features/
    analysis/
      components/
        SpectrumCanvas.tsx
        StatusLine.tsx
      hooks/
        usePanel.ts
      state/
        panel.ts              # редьюсер из урока 25
      index.ts
    config/
      components/
        ConfigEditor.tsx
      index.ts
    runs/
      components/
        RunList.tsx
        RunRow.tsx
      hooks/
        useRuns.ts
      index.ts
  ui/
    Button.tsx
    Field.tsx
    Panel.tsx
    Select.tsx
    DataTable.tsx
    index.ts
  lib/
    dsp.ts
    objects.ts
    fft.worker.ts
  types.ts
  vite-env.d.ts
```

**Публичный интерфейс фичи:**
```ts
// src/features/analysis/index.ts
export { SpectrumCanvas } from './components/SpectrumCanvas';
export { StatusLine } from './components/StatusLine';
export { usePanel } from './hooks/usePanel';
export type { PanelState, PanelAction } from './state/panel';
```

Остальное — внутреннее. `App.tsx` импортирует только это:
```tsx
import { usePanel, SpectrumCanvas, StatusLine } from '@/features/analysis';
import { ConfigEditor } from '@/features/config';
import { RunList, useRuns } from '@/features/runs';
import { Layout, Panel, Button } from '@/ui';
```

**Вынос расчёта в воркер:**

```ts
// src/lib/dsp.ts
import type { FftConfig } from '@/types';

type WorkerRequest = {
  id: number;
  samples: Float32Array;
  config: FftConfig;
};

type WorkerResponse =
  | { id: number; ok: true; bins: Float32Array }
  | { id: number; ok: false; error: string };

let worker: Worker | null = null;
let nextId = 0;
const pending = new Map<number, {
  resolve: (bins: Float32Array) => void;
  reject: (e: Error) => void;
}>();

function getWorker(): Worker {
  if (worker) return worker;

  worker = new Worker(new URL('./fft.worker.ts', import.meta.url), {
    type: 'module',
  });

  worker.onmessage = (e: MessageEvent<WorkerResponse>) => {
    const entry = pending.get(e.data.id);
    if (!entry) return;
    pending.delete(e.data.id);
    if (e.data.ok) entry.resolve(e.data.bins);
    else entry.reject(new Error(e.data.error));
  };

  return worker;
}

export function computeSpectrum(
  samples: Float32Array,
  config: FftConfig,
  signal?: AbortSignal,
): Promise<Float32Array> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException('Aborted', 'AbortError'));
      return;
    }

    const id = nextId++;
    pending.set(id, { resolve, reject });

    signal?.addEventListener('abort', () => {
      pending.delete(id);
      reject(new DOMException('Aborted', 'AbortError'));
    }, { once: true });

    const copy = samples.slice();          // копия — оригинал остаётся у нас
    getWorker().postMessage(
      { id, samples: copy, config } satisfies WorkerRequest,
      [copy.buffer],
    );
  });
}
```

**Разбор.**

**Воркер один на всё приложение**, создаётся лениво при первом вызове. Создавать по воркеру на запрос — дорого, старт занимает десятки миллисекунд.

**Ответы сопоставляются по `id`.** Воркер обрабатывает запросы последовательно, но промисы разрешаются асинхронно — без идентификатора невозможно понять, чей ответ пришёл.

**`WorkerResponse` — размеченное объединение.** Урок 08 продолжает работать и в межпоточном обмене: успех и ошибка не смешиваются.

**Отмена через `AbortSignal`.** Воркер не остановить (он досчитает), но промис отклоняется, и результат отбрасывается. Для настоящей отмены нужен либо `terminate()` воркера, либо проверка флага в `SharedArrayBuffer` внутри цикла расчёта.

**`samples.slice()` перед передачей.** Мы передаём владение буфером, и после `postMessage` он опустеет. Копия защищает исходный массив. Если оригинал больше не нужен — копию можно убрать и сэкономить.

**`satisfies WorkerRequest`** — приём из урока 12. Проверяет структуру сообщения, не сужая тип. Опечатка в имени поля не скомпилируется.

**Проверь, что воркер работает.** Открой DevTools → Sources → там появится отдельный поток. Запусти расчёт на большом массиве и подвигай ползунок — интерфейс должен остаться отзывчивым. Затем временно перенеси расчёт обратно в главный поток и повтори — увидишь разницу немедленно.

---

# Часть 3. Домашка

**1.** Настрой алиасы `@/` в `vite.config.ts` и `tsconfig.json`. Перепиши все относительные импорты. Проверь, что и Vite, и `tsc`, и WebStorm их понимают.

**2.** Добавь `.env` с адресом API и максимальным размером FFT. Типизируй `ImportMetaEnv`. Убедись, что опечатка в имени переменной даёт ошибку компиляции.

**3.** Настрой прокси для `/api` и `/ws`. Проверь, что запрос с фронта уходит на бэкенд без CORS-ошибок (бэкенд можно заменить любой заглушкой).

**4.** Вынеси `SpectrumCanvas` в `lazy`. Собери проект, посмотри в `dist/` — убедись, что появился отдельный чанк. Измерь размер основного бандла до и после.

**5.** Напиши воркер из проработки полностью, с реальным вычислением FFT (можно взять простую реализацию Кули-Тьюки или библиотеку). Замерь время расчёта для 65536 точек в главном потоке и в воркере, сравни отзывчивость интерфейса.

**6.** Найди нарушения слоёв в своём проекте: импорты из `ui/` в `features/`, из `lib/` в React-код, между фичами напрямую. Исправь. Затем настрой правило ESLint `import/no-restricted-paths`, чтобы это не повторилось.

**7.** Собери прод-версию, запусти `preview`. Проверь, что всё работает так же, как в dev. Если что-то сломалось — разберись, почему dev и build расходятся.

**8.** Пул воркеров. Перепиши `dsp.ts` так, чтобы использовалось N воркеров (по числу `navigator.hardwareConcurrency`), а запросы распределялись между свободными. Замерь ускорение на пакете из 20 расчётов.
