# Урок 33. Веб-морда для DSP: архитектура

Начало блока проекта. Новой теории почти нет — есть решения, которые надо принять до того, как написан код, и обоснование каждого.

---

# Часть 1. Теория

## 33.1 Что строим

Панель анализа сигналов в браузере:

- загрузка сигнала из файла или приём потока по WebSocket
- расчёт спектра в Web Worker
- отрисовка спектра и водопада на canvas в реальном времени
- параметры анализа с сохранением в URL
- история прогонов на сервере
- измерительные курсоры, зум, экспорт

Задача выбрана так, чтобы встретились все ограничения настоящего приложения: бинарные данные, высокая частота обновления, тяжёлые вычисления, императивная графика внутри декларативного фреймворка.

## 33.2 Карта состояния

Главное архитектурное решение — **где что живёт**. Ошибка здесь дороже любой другой: неправильно размещённое состояние тянет за собой лишние рендеры, рассинхроны и невозможность поделиться ссылкой.

| Что | Где | Почему |
|---|---|---|
| Параметры FFT | URL | воспроизводимость, ссылка коллеге |
| Режим отображения, тема, единицы | Zustand + persist | глобально, переживает перезагрузку |
| Ход текущего расчёта | `useReducer` | автомат, живёт с компонентом |
| Состояние соединения | Zustand | нужно в нескольких местах, переживает навигацию |
| История прогонов | TanStack Query | серверные данные, кеш |
| Выделение в списке | Zustand | тысячи строк, подписка на срез |
| Последний пакет данных | `useRef` | 60 Гц, рендер не нужен |
| Позиция курсора на графике | `useState` локально | меняется часто, влияет на одну подпись |
| Черновик формы | React Hook Form | ввод не должен вызывать рендер |

Каждая строка — применение правила из предыдущих уроков. Если сомневаешься, вернись к 17.5 (что не должно быть состоянием) и 28.1 (серверное против клиентского).

**Проверка на дублирование.** Одно значение — одно место. Если параметры FFT в URL, их **нет** ни в Zustand, ни в редьюсере. Редьюсер получает снимок конфига в момент старта расчёта и хранит его внутри состояния `running` — это не дубль, а зафиксированный аргумент операции.

## 33.3 Слои

```
UI (React)          декларативный, чистые компоненты
   │
Хуки                состояние, эффекты, связь со слоями ниже
   │
Домен (lib/)        чистые функции: DSP, форматирование, координаты
   │
Инфраструктура      воркер, сокет, API — императивные системы
```

**Правило зависимостей: только вниз.** `lib/` не знает про React, инфраструктура не знает про UI. Проверяется механически — ни одного `import React` ниже слоя хуков.

Практический эффект: домен тестируется без jsdom и без моков (урок 32), а при замене React на что угодно переписывается только верхний слой.

## 33.4 Три контура обновления

Ключевое для производительности решение — разделить данные по частоте изменения:

**Контур 1: пользовательский ввод.** Параметры, кнопки, фильтры. Единицы Гц. Обычный React со всем состоянием и рендерами. Оптимизировать нечего.

**Контур 2: статус и метрики.** Прогресс, частота пакетов, состояние соединения. Единицы Гц (обновление раз в секунду). Состояние React, но агрегированное по таймеру — не на каждое событие.

**Контур 3: данные для отрисовки.** Отсчёты, спектр. Десятки Гц, мегабайты. **React не участвует вообще.** Данные в `useRef`, отрисовка в `requestAnimationFrame`, компонент не перерисовывается.

Это ответ на вопрос «потянет ли React реальное время». Потянет — если не пускать реальное время в React. Приём из урока 20, теперь как архитектурный принцип.

## 33.5 Границы системы

Мест, где данные входят извне, пять. На каждом — валидация (урок 30):

| Граница | Что приходит | Чем проверяем |
|---|---|---|
| URL | параметры вида | `FftConfigSchema.safeParse` |
| API | прогоны | `RunSchema` в `queryFn` |
| Файл | заголовок и отсчёты | схема + проверка длины буфера |
| WebSocket | бинарные пакеты | разбор заголовка, проверка размера |
| Воркер | результат расчёта | размеченное объединение, схема опционально |

Внутри границ код работает с типизированными данными и не проверяет ничего. Это то, к чему мы шли с урока 07.

**Про бинарные данные особо.** Zod для `Float32Array` избыточен — валидация мегабайтного массива поэлементно съест больше, чем сам расчёт. Проверяй **структуру**: длину буфера, корректность заголовка, соответствие размера ожидаемому. Содержимое — доверяй.

## 33.6 Структура файлов

```
src/
  app/
    main.tsx              провайдеры, точка входа
    router.tsx
    Layout.tsx
  features/
    analysis/             расчёт и отображение спектра
      components/         SpectrumCanvas, WaterfallCanvas, StatusLine, Cursors
      hooks/              useAnalysis, useRenderLoop
      state/              panel.ts (редьюсер)
      AnalysisPage.tsx
      index.ts
    source/               источники сигнала
      components/         FileDrop, StreamConnect, GeneratorForm
      hooks/              useSignalSource
      index.ts
    runs/                 история прогонов
      api/                runs.ts, keys.ts, queries.ts
      components/         RunList, RunRow, SaveRunForm
      index.ts
  store/
    settings.ts           тема, единицы, диапазон дБ
    connection.ts         состояние соединения
    selection.ts
  lib/
    dsp/
      fft.ts              преобразование
      window.ts           оконные функции
      scale.ts            дБ, частоты, координаты
      index.ts
    worker/
      fft.worker.ts
      client.ts           обёртка с промисами и пулом
    stream/
      protocol.ts         разбор бинарных пакетов
      client.ts           WebSocket с переподключением
    cn.ts
  ui/                     Button, Panel, Field, Select, DataTable
  test/
    setup.ts, render.tsx, server.ts
  types.ts
```

**Что здесь важно.** `lib/dsp/` и `lib/stream/` — чистая логика, ноль React, полное покрытие тестами. `features/` — сборка. `ui/` — примитивы без доменного знания.

Проверка правильности: **можно ли взять `lib/` целиком и использовать в Node-скрипте?** Если да — слои разделены верно.

## 33.7 Протокол потока

Договоримся о формате пакетов заранее — от этого зависит весь код приёма.

```
[0..3]   magic       'DSP1' (4 байта)
[4]      type        0=meta, 1=samples, 2=error
[5..7]   reserved
[8..11]  sequence    uint32, для обнаружения потерь
[12..15] payloadLen  uint32
[16..]   payload
```

Бинарный формат, а не JSON — на 60 пакетах в секунду по 4096 отсчётов JSON съест процессор на парсинге и утроит трафик.

```ts
// src/lib/stream/protocol.ts
export const MAGIC = 0x44535031;   // 'DSP1'

export type Packet =
  | { type: 'meta'; sampleRate: number; channels: number }
  | { type: 'samples'; sequence: number; data: Float32Array }
  | { type: 'error'; message: string };

export function parsePacket(buf: ArrayBuffer): Packet | null {
  if (buf.byteLength < 16) return null;

  const view = new DataView(buf);
  if (view.getUint32(0) !== MAGIC) return null;

  const type = view.getUint8(4);
  const sequence = view.getUint32(8);
  const payloadLen = view.getUint32(12);

  if (buf.byteLength < 16 + payloadLen) return null;

  switch (type) {
    case 0: {
      if (payloadLen < 8) return null;
      return {
        type: 'meta',
        sampleRate: view.getUint32(16),
        channels: view.getUint32(20),
      };
    }
    case 1: {
      if (payloadLen % 4 !== 0) return null;
      // без копирования — представление поверх того же буфера
      return {
        type: 'samples',
        sequence,
        data: new Float32Array(buf, 16, payloadLen / 4),
      };
    }
    case 2:
      return {
        type: 'error',
        message: new TextDecoder().decode(new Uint8Array(buf, 16, payloadLen)),
      };
    default:
      return null;
  }
}
```

**Разбор.**

**Размеченное объединение снова** — теперь для сетевого протокола. Урок 08 работает от типов до проводов.

**`new Float32Array(buf, 16, n)` без копирования.** Это *представление* поверх существующего буфера, не новый массив. Для мегабайтных пакетов разница принципиальная.

Осторожно: смещение 16 кратно 4, иначе конструктор бросит — `Float32Array` требует выравнивания. Поэтому заголовок и сделан кратным четырём.

**`| null` вместо исключения.** Битый пакет — штатная ситуация в сети, не исключительная. Возврат `null` заставляет вызывающего обработать случай (при `strictNullChecks`), а исключение можно случайно проглотить.

**`sequence` для обнаружения потерь.** Пропуск в нумерации означает потерянный пакет — метрика качества связи, покажем её в статусе.

## 33.8 Что откладываем

Признак здоровой архитектуры — явный список того, чего в ней **нет**:

- аутентификации (внутренний инструмент)
- офлайн-режима
- поддержки мобильных (панель для рабочего стола)
- нескольких каналов одновременно (только моно на первом этапе)
- серверного рендеринга

Каждый пункт — сознательное решение, а не забывчивость. Записывай такие решения: через полгода ты не вспомнишь, было это выбором или упущением.

---

# Часть 2. Проработка

## Задача. Каркас проекта

Собираем скелет: типы, границы, точки входа. Реализация — в следующих уроках.

**Доменные типы — единый источник:**
```ts
// src/types.ts
import { z } from 'zod';

export const WINDOWS = {
  hann:     { label: 'Ханна',      sidelobeDb: -31 },
  hamming:  { label: 'Хэмминга',   sidelobeDb: -42 },
  blackman: { label: 'Блэкмана',   sidelobeDb: -58 },
  rect:     { label: 'Прямоугол.', sidelobeDb: -13 },
} as const satisfies Record<string, { label: string; sidelobeDb: number }>;

export const FFT_SIZES = [256, 512, 1024, 2048, 4096, 8192, 16384] as const;

export type WindowFn = keyof typeof WINDOWS;
export type FftSize = typeof FFT_SIZES[number];

export const FftConfigSchema = z.object({
  size: z.union([
    z.literal(256), z.literal(512), z.literal(1024), z.literal(2048),
    z.literal(4096), z.literal(8192), z.literal(16384),
  ]),
  window: z.enum(['hann', 'hamming', 'blackman', 'rect']),
  overlap: z.number().min(0).max(0.95),
  averaging: z.number().int().min(1).max(64),
});

export type FftConfig = z.infer<typeof FftConfigSchema>;

export const DEFAULT_CONFIG: FftConfig = {
  size: 2048, window: 'hann', overlap: 0.5, averaging: 1,
};
```

**Источник сигнала — размеченное объединение:**
```ts
export type SignalSource =
  | { kind: 'none' }
  | { kind: 'file'; name: string; sampleRate: number; samples: Float32Array }
  | { kind: 'stream'; url: string; sampleRate: number }
  | { kind: 'generator'; freqHz: number; amplitude: number; sampleRate: number; noiseDb: number };
```

Три способа получить данные, каждый со своими параметрами. Компилятор не даст спросить `samples` у потока или `url` у файла.

**Спектр:**
```ts
export type Spectrum = {
  readonly magnitudesDb: Float32Array;
  readonly binHz: number;
  readonly sampleRate: number;
  readonly computedAt: number;
};
```

Храним уже в дБ — переводить при каждой отрисовке дорого, а обратно почти никогда не нужно. `binHz` рядом с данными, чтобы отрисовка не пересчитывала его из конфига.

**Точка входа:**
```tsx
// src/app/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClientProvider } from '@tanstack/react-query';
import { RouterProvider } from 'react-router-dom';
import { queryClient } from './queryClient';
import { router } from './router';
import { ThemeProvider } from './ThemeProvider';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>
        <RouterProvider router={router} />
      </ThemeProvider>
    </QueryClientProvider>
  </StrictMode>
);
```

**`StrictMode` оставляем включённым.** Двойной вызов эффектов (урок 19) немедленно покажет неправильную очистку — а у нас будут сокеты, воркеры и `requestAnimationFrame`, где утечка очистки означает висящее соединение или два цикла отрисовки одновременно. Это именно тот проект, где StrictMode приносит максимум пользы.

**Скелет чистого домена:**
```ts
// src/lib/dsp/scale.ts — ноль React, ноль зависимостей
export const binToHz = (bin: number, sampleRate: number, size: number): number =>
  (bin * sampleRate) / size;

export const hzToBin = (hz: number, sampleRate: number, size: number): number =>
  Math.round((hz * size) / sampleRate);

export const magnitudeToDb = (m: number, ref = 1): number =>
  20 * Math.log10(Math.max(m / ref, 1e-12));      // защита от log(0)

export function formatFreq(hz: number, unit: 'hz' | 'khz'): string {
  return unit === 'khz'
    ? `${(hz / 1000).toFixed(3)} кГц`
    : `${hz.toFixed(1)} Гц`;
}

/** Координаты для отрисовки — чистая функция, тестируется без canvas */
export function binsToPoints(
  bins: Float32Array,
  width: number,
  height: number,
  minDb: number,
  maxDb: number,
): Float32Array {
  const points = new Float32Array(bins.length * 2);
  const range = maxDb - minDb;

  for (let i = 0; i < bins.length; i++) {
    const db = Math.min(maxDb, Math.max(minDb, bins[i] ?? minDb));
    points[i * 2] = (i / (bins.length - 1)) * width;
    points[i * 2 + 1] = height - ((db - minDb) / range) * height;
  }
  return points;
}
```

**`binsToPoints` — важное решение.** Расчёт координат вынесен из компонента в чистую функцию. Теперь он тестируется обычным `expect` без jsdom и моков canvas (урок 32, задача 7). В компоненте останется только `ctx.moveTo/lineTo` по готовым точкам.

**`Math.max(m/ref, 1e-12)`** — тишина даёт нулевую магнитуду, `log10(0)` это `-Infinity`, и вся отрисовка ломается. Порог -240 дБ ниже любого реального сигнала.

**Что проверить прямо сейчас.** Напиши три теста на `binsToPoints`: правильная длина результата, первая точка в `x=0`, значение ниже `minDb` прижимается к нижнему краю. Если они проходят — граница между доменом и UI проведена правильно, и дальше можно строить на этом фундаменте.

---

# Часть 3. Домашка

**1.** Заполни карту состояния из 33.2 для своего варианта проекта. Для каждой строки напиши, что сломается при неправильном размещении.

**2.** Реализуй `parsePacket` полностью и покрой тестами: валидный пакет каждого типа, битый magic, обрезанный буфер, некратная длина payload, неизвестный тип.

**3.** Проверь правило зависимостей: настрой ESLint-правило, запрещающее импорт React в `src/lib/**`. Убедись, что оно срабатывает.

**4.** Напиши генератор тестового сигнала: сумма синусоид с заданными частотами и амплитудами плюс белый шум заданного уровня. Чистая функция, покрытая тестами (проверь амплитуду, период, что шум не меняет среднее).

**5.** Опиши схемы Zod для всех пяти границ из 33.5. Для бинарных данных объясни, что именно валидируешь и что оставляешь на доверии.

**6.** Собери каркас: структура папок, точка входа, роутер, три страницы-заглушки, провайдеры. Запусти, убедись, что навигация и тема работают.

**7.** Реализуй `binsToPoints` и покрой тестами. Затем добавь логарифмическую шкалу по частоте (для аудио это нужнее линейной) — как изменится сигнатура и тесты?

**8.** Архитектурное. Составь список того, чего в проекте сознательно не будет, с обоснованием каждого пункта. Затем выбери один и опиши, что придётся изменить, если требование появится через полгода.
