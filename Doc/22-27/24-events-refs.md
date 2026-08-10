# Урок 24. Типы событий и refs

Справочный урок. Здесь мало концепций и много конкретики, которую надо один раз посмотреть и потом узнавать.

---

# Часть 1. Теория

## 24.1 Синтетические события

React не вешает обработчики на каждый узел. Он использует делегирование: один слушатель на корень приложения, а в обработчик передаёт **синтетическое событие** — обёртку над нативным, одинаковую во всех браузерах.

```tsx
function handle(e: React.MouseEvent<HTMLButtonElement>) {
  e.preventDefault();
  e.stopPropagation();
  e.nativeEvent;              // настоящее браузерное событие
  e.currentTarget;            // элемент с обработчиком — типизирован
  e.target;                   // элемент, где произошло — EventTarget, НЕ типизирован
}
```

**`currentTarget` против `target`** — важное различие:
- `currentTarget` — элемент, на котором висит обработчик. Тип известен из дженерика
- `target` — элемент, где событие возникло; при всплытии это может быть потомок. Тип `EventTarget`, приводить приходится вручную

Правило: **используй `currentTarget`**, если не нужна именно точка возникновения.

## 24.2 Таблица типов событий

```tsx
React.MouseEvent<T>          // click, mouseDown, mouseEnter
React.KeyboardEvent<T>       // keyDown, keyUp
React.ChangeEvent<T>         // change у input/select/textarea
React.FormEvent<T>           // submit, reset
React.FocusEvent<T>          // focus, blur
React.PointerEvent<T>        // pointerDown — предпочтительнее mouse для тач
React.WheelEvent<T>          // wheel
React.DragEvent<T>           // drag and drop
React.ClipboardEvent<T>      // copy, paste
React.TouchEvent<T>          // touchStart
```

`T` — тип элемента: `HTMLButtonElement`, `HTMLInputElement`, `HTMLCanvasElement`, `HTMLDivElement`.

**Самое частое:**
```tsx
onChange={(e: React.ChangeEvent<HTMLInputElement>) => e.target.value}
onChange={(e: React.ChangeEvent<HTMLSelectElement>) => e.target.value}
onClick={(e: React.MouseEvent<HTMLButtonElement>) => ...}
onSubmit={(e: React.FormEvent<HTMLFormElement>) => { e.preventDefault(); }}
onKeyDown={(e: React.KeyboardEvent<HTMLInputElement>) => e.key === 'Enter'}
```

**В инлайн-обработчиках аннотация не нужна** — тип выводится из атрибута:
```tsx
<input onChange={e => setValue(e.target.value)} />   // e типизирован автоматически
```
Аннотируй только вынесенные функции.

**Тип обработчика целиком:**
```tsx
const handle: React.MouseEventHandler<HTMLButtonElement> = e => { };
const change: React.ChangeEventHandler<HTMLInputElement> = e => { };
```
Удобно, когда функция объявляется отдельно — тип параметра выводится сам.

## 24.3 Формы

```tsx
function SearchForm({ onSearch }: { onSearch: (q: string) => void }) {
  const [q, setQ] = useState('');

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();               // обязательно — иначе перезагрузка страницы
    onSearch(q);
  };

  return (
    <form onSubmit={handleSubmit}>
      <input value={q} onChange={e => setQ(e.target.value)} />
      <button type="submit">Найти</button>
    </form>
  );
}
```

**`type="button"` для кнопок внутри формы**, которые не отправляют. По умолчанию `<button>` внутри `<form>` имеет `type="submit"` — классический источник «страница перезагружается при клике».

**Неуправляемая форма** через `FormData`:
```tsx
const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
  e.preventDefault();
  const data = new FormData(e.currentTarget);
  const size = Number(data.get('size'));
};
```
Меньше состояния, но нет валидации на лету. Для больших форм — React Hook Form (урок 30).

## 24.4 Refs на DOM

```tsx
const inputRef = useRef<HTMLInputElement>(null);

useEffect(() => {
  inputRef.current?.focus();
}, []);

return <input ref={inputRef} />;
```

**`| null` обязателен** — до монтирования там пусто, и после размонтирования React обнуляет.

**`?.` при каждом обращении** — не `!`. Обращение к `current` вне эффекта может произойти до монтирования.

**Callback ref** — когда нужно среагировать на появление узла:
```tsx
const [node, setNode] = useState<HTMLCanvasElement | null>(null);
return <canvas ref={setNode} />;
```
Состояние вместо ref, поэтому появление узла вызывает рендер и эффекты с зависимостью `[node]`. Полезно, когда узел появляется условно.

Функция-ref вызывается с узлом при монтировании и с `null` при размонтировании:
```tsx
<div ref={el => { if (el) observer.observe(el); }} />
```
В React 19 такая функция может вернуть функцию очистки — как эффект.

## 24.5 `useImperativeHandle`

Даёт родителю императивный доступ к «методам» ребёнка:

```tsx
export type ChartHandle = {
  redraw: () => void;
  exportPng: () => string;
};

function Chart({ ref, data }: Props & { ref?: React.Ref<ChartHandle> }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useImperativeHandle(ref, () => ({
    redraw: () => draw(canvasRef.current, data),
    exportPng: () => canvasRef.current?.toDataURL() ?? '',
  }), [data]);

  return <canvas ref={canvasRef} />;
}
```

```tsx
const chartRef = useRef<ChartHandle>(null);
<Chart ref={chartRef} data={bins} />
<button onClick={() => chartRef.current?.redraw()}>Перерисовать</button>
```

**Применяй редко.** Императивный доступ — выход из декларативной модели, и обычно его хотят там, где нужен просто props. Законные случаи: фокус, прокрутка, воспроизведение медиа, экспорт из canvas, интеграция с императивной библиотекой.

Синтаксис выше — для React 19, где `ref` обычный props. В 18 и раньше — через `forwardRef`.

## 24.6 Типизация нативных событий

Внутри эффектов события **не** синтетические — там нативные типы, без префикса `React.`:

```tsx
useEffect(() => {
  const onKey = (e: KeyboardEvent) => {          // не React.KeyboardEvent!
    if (e.key === 'Escape') close();
  };
  window.addEventListener('keydown', onKey);
  return () => window.removeEventListener('keydown', onKey);
}, []);
```

Смешать легко: `React.KeyboardEvent` не подойдёт для `addEventListener` и наоборот.

**Типобезопасный хук для слушателей:**
```tsx
function useEventListener<K extends keyof WindowEventMap>(
  type: K,
  handler: (e: WindowEventMap[K]) => void,
) {
  const ref = useRef(handler);
  ref.current = handler;

  useEffect(() => {
    const listener = (e: WindowEventMap[K]) => ref.current(e);
    window.addEventListener(type, listener);
    return () => window.removeEventListener(type, listener);
  }, [type]);
}
```

`WindowEventMap` — встроенная карта «имя события → тип». `useEventListener('keydown', e => e.key)` даст правильный тип без аннотаций. Приём с ref из урока 20 держит обработчик актуальным, не пересоздавая подписку.

Аналогично `DocumentEventMap`, `HTMLElementEventMap`.

## 24.7 Частые ошибки

**`e.target.value` в делегированном обработчике:**
```tsx
<div onChange={e => e.target.value}>   // ❌ target это EventTarget
```
Нужен `currentTarget` или приведение с проверкой.

**Забытый `preventDefault` в форме** — страница перезагружается, состояние теряется.

**Обработчик, вызванный вместо переданного:**
```tsx
<button onClick={handleDelete(id)} />       // ❌ вызовется при рендере
<button onClick={() => handleDelete(id)} /> // ✅
```

**`ref` на компоненте вместо DOM-узла:**
```tsx
<MyComponent ref={r} />    // до React 19 — предупреждение, нужен forwardRef
```

---

# Часть 2. Проработка

## Задача. Интерактивный canvas со спектром

Курсор, зум колесом, выделение диапазона мышью, горячие клавиши — всё на типизированных событиях.

```tsx
// src/SpectrumCanvas.tsx
import { useRef, useState, useCallback } from 'react';

type Range = { from: number; to: number };

type Props = {
  bins: Float32Array | null;
  sampleRate: number;
  onSelect?: (range: Range) => void;
};

export function SpectrumCanvas({ bins, sampleRate, onSelect }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [cursor, setCursor] = useState<{ hz: number; db: number } | null>(null);
  const [drag, setDrag] = useState<{ startX: number; currentX: number } | null>(null);
  const [zoom, setZoom] = useState(1);

  // перевод координаты canvas в частоту
  const xToHz = useCallback((x: number, width: number) => {
    const nyquist = sampleRate / 2;
    return (x / width) * (nyquist / zoom);
  }, [sampleRate, zoom]);

  const handleMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    setCursor({
      hz: xToHz(x, rect.width),
      db: -120 + (1 - y / rect.height) * 120,
    });

    if (drag) setDrag(d => d && { ...d, currentX: x });
  };

  const handleDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    setDrag({ startX: x, currentX: x });
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handleUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drag) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const [a, b] = [drag.startX, drag.currentX].sort((x, y) => x - y);

    if (Math.abs(b - a) > 4) {
      onSelect?.({ from: xToHz(a, rect.width), to: xToHz(b, rect.width) });
    }
    setDrag(null);
    e.currentTarget.releasePointerCapture(e.pointerId);
  };

  const handleWheel = (e: React.WheelEvent<HTMLCanvasElement>) => {
    setZoom(z => Math.min(64, Math.max(1, z * (e.deltaY < 0 ? 1.2 : 1 / 1.2))));
  };

  const handleKey = (e: React.KeyboardEvent<HTMLCanvasElement>) => {
    if (e.key === 'Escape') { setDrag(null); setZoom(1); }
    if (e.key === '+' || e.key === '=') setZoom(z => Math.min(64, z * 1.5));
    if (e.key === '-') setZoom(z => Math.max(1, z / 1.5));
  };

  return (
    <div className="spectrum">
      <canvas
        ref={canvasRef}
        width={800}
        height={300}
        tabIndex={0}
        onPointerMove={handleMove}
        onPointerDown={handleDown}
        onPointerUp={handleUp}
        onPointerLeave={() => setCursor(null)}
        onWheel={handleWheel}
        onKeyDown={handleKey}
      />
      {cursor && (
        <div className="readout">
          {cursor.hz.toFixed(1)} Гц / {cursor.db.toFixed(1)} дБ
        </div>
      )}
    </div>
  );
}
```

**Разбор.**

**`e.currentTarget` везде, ни одного `e.target`.** Обработчик висит на самом canvas, `currentTarget` типизирован как `HTMLCanvasElement`, и `getBoundingClientRect`, `setPointerCapture` доступны без приведений.

**`getBoundingClientRect()` вместо `offsetX`.** Свойства `offsetX/offsetY` есть, но считаются от ближайшего позиционированного предка и ломаются при CSS-трансформациях. Разница `clientX - rect.left` надёжнее.

**Pointer events вместо mouse.** Один набор обработчиков работает для мыши, тача и стилуса. `setPointerCapture` продолжает получать события, даже когда курсор ушёл за пределы canvas — без него выделение обрывалось бы на границе.

**`tabIndex={0}` на canvas.** Без него элемент не получает фокус, и `onKeyDown` не сработает. Частая причина «клавиши не работают».

**`setDrag(d => d && { ...d, currentX: x })`** — функциональная форма плюс защита от `null`. Между событиями состояние могло сброситься.

**Курсор в состоянии, но не данные.** `cursor` меняется на каждое движение мыши, то есть десятки раз в секунду. Это допустимо, потому что перерисовывается только маленький `<div className="readout">`. Если бы от него зависела отрисовка спектра — надо было бы в ref, как в уроке 20.

**Горячие клавиши глобально** — уже нативное событие:
```tsx
useEventListener('keydown', e => {
  if (e.key === ' ' && !isInput(e.target)) {
    e.preventDefault();
    toggleRun();
  }
});

const isInput = (t: EventTarget | null): boolean =>
  t instanceof HTMLElement && ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName);
```

`e.target` здесь `EventTarget | null` — приходится сужать через `instanceof` (урок 07). Проверка нужна, чтобы пробел в поле ввода не запускал анализ.

**Императивный доступ — экспорт картинки:**
```tsx
export type SpectrumHandle = { exportPng: () => void };

useImperativeHandle(ref, () => ({
  exportPng: () => {
    const url = canvasRef.current?.toDataURL('image/png');
    if (!url) return;
    const a = document.createElement('a');
    a.href = url;
    a.download = `spectrum-${Date.now()}.png`;
    a.click();
  },
}), []);
```

Законный случай: результат не описывается состоянием, это разовое действие над DOM-узлом.

---

# Часть 3. Домашка

**1.** Для каждого — правильный тип события и элемента:
```tsx
<textarea onChange={e => ...} />
<form onSubmit={e => ...} />
<div onDrop={e => ...} />
<input onKeyDown={e => ...} />
<select onBlur={e => ...} />
```

**2.** Почему не компилируется и как исправить двумя способами?
```tsx
<div onClick={e => console.log(e.target.dataset.id)} />
```

**3.** Поле поиска с двумя поведениями: Enter отправляет, Escape очищает и снимает фокус. Реализуй, типизируй, не забудь `preventDefault` где нужно.

**4.** Реализуй `useEventListener` из 24.6 полностью, с перегрузками для `window`, `document` и произвольного элемента через ref. Проверь вывод типа события во всех трёх случаях.

**5.** Drag-and-drop переупорядочивание списка прогонов на нативных событиях (`onDragStart`, `onDragOver`, `onDrop`). Типизируй `dataTransfer`. Проверь, что состояние строк едет за данными (урок 16).

**6.** `useImperativeHandle`: компонент `ConfigForm` с методами `focus()`, `reset()`, `validate(): boolean`. Опиши тип handle, используй из родителя.

**7.** Модалка, закрывающаяся по Escape и по клику вне. Второе требует нативного слушателя на `document` и проверки, что клик был вне контейнера. Осторожно с порядком: клик, открывший модалку, не должен её сразу закрыть.

**8.** Объясни разницу и когда что использовать:
```tsx
const ref = useRef<HTMLDivElement>(null);
const [node, setNode] = useState<HTMLDivElement | null>(null);
<div ref={ref} />
<div ref={setNode} />
```
Приведи случай, где первый вариант не сработает, а второй — да.
