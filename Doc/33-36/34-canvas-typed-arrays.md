# Урок 34. Canvas и работа с `Float32Array`

Императивная графика внутри декларативного фреймворка. Плюс типизированные массивы — то, чего в обычном фронтенде почти не встречается, а у нас основа всего.

---

# Часть 1. Теория

## 34.1 Типизированные массивы

```ts
new Float32Array(1024)                    // 4096 байт, заполнены нулями
new Float32Array([1, 2, 3])
new Float32Array(buffer, byteOffset, length)   // ПРЕДСТАВЛЕНИЕ, без копирования
```

Три уровня, которые важно различать:

- **`ArrayBuffer`** — сырая память, обратиться напрямую нельзя
- **`TypedArray`** (`Float32Array`, `Int16Array`, `Uint8Array`) — типизированное окно в буфер
- **`DataView`** — доступ с произвольным смещением и контролем порядка байт

```ts
const buf = new ArrayBuffer(1024);
const floats = new Float32Array(buf);          // 256 элементов
const bytes = new Uint8Array(buf);             // 1024 элемента, ТЕ ЖЕ данные
floats[0] = 1;
bytes[0];                                       // изменился — общая память
```

**Копия против представления** — самое частое место ошибок:
```ts
const view = new Float32Array(buf, 16, 256);   // ссылается на buf
const copy = buf.slice(16, 16 + 1024);          // новая память
const copy2 = floats.slice(0, 100);             // новый массив
const view2 = floats.subarray(0, 100);          // представление!
```
`slice` копирует, `subarray` — нет. Перепутал — либо лишние мегабайты, либо неожиданная мутация чужих данных.

**Порядок байт.** `TypedArray` использует порядок платформы (почти всегда little-endian), `DataView` — явно указываемый:
```ts
view.getUint32(0);          // big-endian по умолчанию!
view.getUint32(0, true);    // little-endian
```
Для сетевых протоколов — всегда `DataView` с явным флагом. Иначе код сломается на другой архитектуре.

**Выравнивание.** `new Float32Array(buf, offset)` требует `offset % 4 === 0`, иначе исключение. Проектируй заголовки протоколов кратными.

**Производительность.** Типизированные массивы в JIT работают на скорости, близкой к нативной, — движок знает тип элементов и не боксит. Но `for` быстрее `forEach`/`map`, а обход по возрастанию индекса быстрее произвольного (кеш процессора). Всё как в C, только без указателей.

## 34.2 Canvas 2D

```tsx
const ctx = canvas.getContext('2d');
ctx.clearRect(0, 0, w, h);
ctx.beginPath();
ctx.moveTo(x, y);
ctx.lineTo(x, y);
ctx.stroke();
```

**Один путь вместо тысячи вызовов.** Каждый `stroke()` — отдельная операция растеризации. Собери весь путь и обведи один раз:
```ts
ctx.beginPath();
for (let i = 0; i < n; i++) ctx.lineTo(px[i], py[i]);
ctx.stroke();                    // ✅ один вызов
```

**Пропуск невидимых точек.** При 8192 бинах на 800 пикселях на один пиксель приходится десять точек. Рисовать все бессмысленно — вместо этого для каждого пикселя бери min/max и рисуй вертикальный отрезок:

```ts
function drawMinMax(ctx, bins, width, height, minDb, maxDb) {
  const perPixel = bins.length / width;
  ctx.beginPath();

  for (let x = 0; x < width; x++) {
    const from = Math.floor(x * perPixel);
    const to = Math.min(bins.length, Math.floor((x + 1) * perPixel));

    let lo = Infinity, hi = -Infinity;
    for (let i = from; i < to; i++) {
      const v = bins[i]!;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }

    const y1 = toY(hi, height, minDb, maxDb);
    const y2 = toY(lo, height, minDb, maxDb);
    ctx.moveTo(x + 0.5, y1);
    ctx.lineTo(x + 0.5, y2);
  }
  ctx.stroke();
}
```

Это стандартный приём отрисовки осциллограмм: сложность падает с O(бинов) до O(ширины), а картинка получается точнее — пики не теряются при прореживании.

**`x + 0.5`** — линия толщиной 1 пиксель, нарисованная по целой координате, размазывается на два пикселя. Полпикселя сдвига дают чёткую линию.

## 34.3 Разрешение и `devicePixelRatio`

Атрибуты `width`/`height` — размер буфера. CSS-размер — размер отображения. Они независимы.

```tsx
useEffect(() => {
  const canvas = canvasRef.current;
  if (!canvas) return;

  const observer = new ResizeObserver(([entry]) => {
    if (!entry) return;
    const dpr = window.devicePixelRatio || 1;
    const { width, height } = entry.contentRect;

    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);

    const ctx = canvas.getContext('2d');
    ctx?.scale(dpr, dpr);              // рисуем в CSS-пикселях
  });

  observer.observe(canvas);
  return () => observer.disconnect();
}, []);
```

Без этого на экране с масштабированием (типичный ноутбук — 125-200%) линия будет мыльной.

**Изменение `canvas.width` сбрасывает состояние контекста** — трансформации, цвета, толщину линии. Настраивай после ресайза, а не один раз при монтировании.

## 34.4 Слои

Не всё меняется с одинаковой частотой. Раздели на несколько canvas друг над другом:

```tsx
<div className="relative">
  <canvas ref={gridRef}    className="absolute inset-0" />   {/* сетка: при ресайзе */}
  <canvas ref={spectrumRef} className="absolute inset-0" />  {/* спектр: 60 Гц */}
  <canvas ref={cursorRef}   className="absolute inset-0" />  {/* курсор: при движении мыши */}
</div>
```

Сетка с подписями частот рисуется дорого (текст — самая медленная операция canvas), но меняется только при ресайзе или зуме. Перерисовывать её 60 раз в секунду — чистая потеря.

Композицию слоёв делает браузер на GPU, это бесплатно.

## 34.5 Водопад

Спектрограмма — история спектров, время по вертикали. Наивная реализация хранит N последних спектров и перерисовывает всё каждый кадр: O(N × ширина) операций.

**Приём: сдвиг существующего изображения.**
```ts
function pushWaterfallRow(ctx: CanvasRenderingContext2D, bins: Float32Array, w: number, h: number) {
  // сдвигаем всё вниз на 1 пиксель
  ctx.drawImage(ctx.canvas, 0, 1);

  // рисуем новую строку сверху
  const row = ctx.createImageData(w, 1);
  for (let x = 0; x < w; x++) {
    const db = sampleBin(bins, x, w);
    const [r, g, b] = colormap((db - MIN_DB) / (MAX_DB - MIN_DB));
    const o = x * 4;
    row.data[o] = r; row.data[o+1] = g; row.data[o+2] = b; row.data[o+3] = 255;
  }
  ctx.putImageData(row, 0, 0);
}
```

`drawImage` canvas в себя же — аппаратно ускоренная операция. Рисуется только одна новая строка вместо всей истории.

**Альтернатива — кольцевой буфер** с `putImageData` в позицию `head` и двумя `drawImage` при выводе. Быстрее, но сложнее; начинай с первого варианта.

**Цветовая карта.** Не используй hue-градиент (радугу) — она визуально искажает данные, создавая ложные границы там, где их нет. Бери перцептивно равномерные: viridis, magma, inferno. Таблицу на 256 значений считай один раз:

```ts
const COLORMAP = buildViridis(256);      // Uint8Array(256 * 3)

function colormap(t: number): [number, number, number] {
  const i = Math.max(0, Math.min(255, Math.round(t * 255))) * 3;
  return [COLORMAP[i]!, COLORMAP[i+1]!, COLORMAP[i+2]!];
}
```

## 34.6 Когда canvas 2D не хватает

Порог примерно такой:

- **до 100k точек, 60 Гц** — canvas 2D справляется
- **больше, или прозрачность, или 3D** — WebGL

WebGL напрямую многословен; для графиков берут `regl`, `pixi.js` или пишут минимальный шейдер. Выигрыш: точки грузятся в GPU-буфер один раз, отрисовка почти бесплатна.

Для нашей задачи (8192 бина) canvas 2D с min/max-прореживанием достаточно с большим запасом. WebGL понадобится, если добавишь 3D-водопад или десяток каналов одновременно.

**`OffscreenCanvas`** — отрисовка прямо из воркера, главный поток вообще не участвует:
```ts
const offscreen = canvas.transferControlToOffscreen();
worker.postMessage({ canvas: offscreen }, [offscreen]);
```
Поддержка есть везде, кроме старых Safari. Мощный приём, но усложняет: курсоры и события всё равно остаются в главном потоке.

---

# Часть 2. Проработка

## Задача. Компонент спектра

```tsx
// src/features/analysis/components/SpectrumCanvas.tsx
import { useRef, useEffect, useCallback } from 'react';
import { useSettings } from '@/store/settings';
import { drawSpectrum, drawGrid } from '@/lib/dsp/draw';

type Props = {
  /** Источник данных — читается в цикле отрисовки, не через props */
  getBins: () => Float32Array | null;
  sampleRate: number;
  zoom: number;
};

export function SpectrumCanvas({ getBins, sampleRate, zoom }: Props) {
  const gridRef = useRef<HTMLCanvasElement>(null);
  const dataRef = useRef<HTMLCanvasElement>(null);
  const sizeRef = useRef({ width: 0, height: 0, dpr: 1 });
  const frameRef = useRef<number | null>(null);

  const dbRange = useSettings(s => s.dbRange);
  const showGrid = useSettings(s => s.showGrid);

  // --- ресайз: настраиваем оба слоя ---
  useEffect(() => {
    const container = dataRef.current?.parentElement;
    if (!container) return;

    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      const dpr = window.devicePixelRatio || 1;
      const { width, height } = entry.contentRect;
      sizeRef.current = { width, height, dpr };

      for (const canvas of [gridRef.current, dataRef.current]) {
        if (!canvas) continue;
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
        canvas.getContext('2d')?.scale(dpr, dpr);
      }

      // сетка перерисовывается только здесь
      const gridCtx = gridRef.current?.getContext('2d');
      if (gridCtx && showGrid) {
        drawGrid(gridCtx, width, height, sampleRate, zoom, dbRange);
      }
    });

    observer.observe(container);
    return () => observer.disconnect();
  }, [sampleRate, zoom, dbRange, showGrid]);

  // --- цикл отрисовки данных ---
  useEffect(() => {
    const ctx = dataRef.current?.getContext('2d');
    if (!ctx) return;

    const draw = () => {
      const bins = getBins();
      const { width, height } = sizeRef.current;

      if (bins && width > 0) {
        ctx.clearRect(0, 0, width, height);
        drawSpectrum(ctx, bins, width, height, dbRange.min, dbRange.max);
      }
      frameRef.current = requestAnimationFrame(draw);
    };

    frameRef.current = requestAnimationFrame(draw);
    return () => {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
    };
  }, [getBins, dbRange]);

  return (
    <div className="relative h-72 w-full">
      <canvas ref={gridRef} className="absolute inset-0 h-full w-full" />
      <canvas ref={dataRef} className="absolute inset-0 h-full w-full" />
    </div>
  );
}
```

**Разбор.**

**`getBins: () => Float32Array | null` вместо `bins: Float32Array`.** Это главное архитектурное решение компонента. Данные приходят 60 раз в секунду; если передавать их через props, компонент перерисовывался бы 60 раз в секунду вместе со всем поддеревом.

Вместо этого родитель даёт **функцию чтения**, а цикл отрисовки вызывает её каждый кадр. React не участвует в потоке данных вообще — контур 3 из урока 33.

**Два слоя, две частоты.** Сетка перерисовывается в обработчике ресайза и при смене параметров. Данные — каждый кадр. Текст с подписями частот рисуется десятки раз за сессию вместо десятков раз в секунду.

**`sizeRef` вместо состояния.** Размеры нужны циклу отрисовки, но их изменение не должно вызывать рендер — за перерисовку отвечает `requestAnimationFrame`.

**Настройки через селекторы Zustand** (урок 29). `dbRange` меняется редко, при изменении эффект пересоздаётся — это правильно, диапазон нужен в замыкании цикла.

**Отрисовка — чистая функция:**
```ts
// src/lib/dsp/draw.ts — ноль React
export function drawSpectrum(
  ctx: CanvasRenderingContext2D,
  bins: Float32Array,
  width: number,
  height: number,
  minDb: number,
  maxDb: number,
): void {
  const range = maxDb - minDb;
  const perPixel = bins.length / width;
  const toY = (db: number) =>
    height - ((Math.min(maxDb, Math.max(minDb, db)) - minDb) / range) * height;

  ctx.strokeStyle = getComputedStyle(ctx.canvas).getPropertyValue('--color-signal');
  ctx.lineWidth = 1;
  ctx.beginPath();

  if (perPixel <= 1) {
    // точек меньше пикселей — рисуем ломаную
    for (let i = 0; i < bins.length; i++) {
      const x = (i / (bins.length - 1)) * width;
      const y = toY(bins[i] ?? minDb);
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
  } else {
    // точек больше — вертикальные отрезки min/max на пиксель
    for (let x = 0; x < width; x++) {
      const from = Math.floor(x * perPixel);
      const to = Math.min(bins.length, Math.floor((x + 1) * perPixel));

      let lo = Infinity, hi = -Infinity;
      for (let i = from; i < to; i++) {
        const v = bins[i]!;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (lo === Infinity) continue;

      ctx.moveTo(x + 0.5, toY(hi));
      ctx.lineTo(x + 0.5, toY(lo));
    }
  }

  ctx.stroke();
}
```

**Два режима по плотности.** При 512 бинах на 800 пикселей — ломаная. При 16384 — min/max. Переключение автоматическое, вызывающий об этом не знает.

**Цвет из CSS-переменной.** Тема меняется атрибутом на `<html>` (урок 31), canvas читает актуальное значение при отрисовке. Смена темы работает без единого рендера React.

**Использование в странице:**
```tsx
export function AnalysisPage() {
  const [config] = useConfigFromUrl();
  const { spectrumRef, state, run, cancel } = useAnalysis(config);

  // функция чтения — стабильная ссылка, эффект не пересоздаётся
  const getBins = useCallback(() => spectrumRef.current, [spectrumRef]);

  return (
    <Panel title="Спектр" actions={<StatusLine state={state} />}>
      <SpectrumCanvas
        getBins={getBins}
        sampleRate={config.sampleRate ?? 44100}
        zoom={1}
      />
    </Panel>
  );
}
```

`useCallback` здесь обязателен: `getBins` попадает в зависимости эффекта с циклом отрисовки. Нестабильная ссылка означала бы пересоздание цикла на каждом рендере — ровно та ловушка из урока 19.

**Проверь работу.** Открой профайлер React, запусти поток данных. `SpectrumCanvas` **не должен появляться в списке перерисованных** вообще — при том, что картинка обновляется 60 раз в секунду. Если появляется, где-то данные всё-таки текут через props.

---

# Часть 3. Домашка

**1.** Реализуй `drawGrid`: горизонтальные линии по дБ с подписями, вертикальные по частоте с логарифмическим или линейным шагом. Учти, что подписи не должны налезать друг на друга при узком окне.

**2.** Разберись с `slice` и `subarray`. Напиши тест, показывающий разницу: измени элемент через одно представление, проверь через другое.

**3.** Реализуй `buildViridis(n)` — таблицу цветовой карты. Затем нарисуй градиентную полосу-легенду рядом с водопадом.

**4.** Водопад через `drawImage` со сдвигом. Замерь время кадра при 4096 бинах и высоте 512 строк. Затем реализуй через хранение массива спектров и полную перерисовку — сравни.

**5.** `devicePixelRatio`. Отрисуй линию без учёта dpr и с учётом, сделай скриншоты на экране с масштабированием 150%. Объясни, почему `ctx.scale(dpr, dpr)` нужно вызывать после каждого изменения `canvas.width`.

**6.** Измерительные курсоры на третьем слое: вертикальная линия по движению мыши, подпись с частотой и уровнем, режим двух курсоров с показом разности. Проверь, что при движении мыши перерисовывается только слой курсора.

**7.** Прореживание. Сгенерируй сигнал с узким пиком, отрисуй 65536 бинов на 800 пикселях двумя способами: взятием каждой N-й точки и min/max. Покажи, что первый способ теряет пик.

**8.** `OffscreenCanvas`. Перенеси отрисовку спектра в воркер. Замерь загрузку главного потока до и после через Performance-панель. Опиши, что усложнилось в коде.
