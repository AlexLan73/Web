# Урок 14. Компонент как чистая функция, JSX

Начало блока React. Главное здесь — не синтаксис, а смена модели: ты перестаёшь описывать *как менять UI* и начинаешь описывать *как он выглядит при данном состоянии*.

---

# Часть 1. Теория

## 14.1 Императивный и декларативный подход

**Императивно** (jQuery, прямая работа с DOM, большинство GUI-фреймворков):
```js
const el = document.getElementById('status');
el.textContent = 'Загрузка';
el.classList.add('busy');
// ...позже
el.textContent = 'Готово';
el.classList.remove('busy');
el.classList.add('done');
```
Ты отвечаешь за каждый переход. Число возможных путей растёт комбинаторно, и любой пропущенный переход — рассинхрон UI с данными.

**Декларативно** (React):
```jsx
function Status({ state }) {
  if (state === 'loading') return <span className="busy">Загрузка</span>;
  return <span className="done">Готово</span>;
}
```
Ты описываешь результат для каждого состояния. Переходы вычисляет React.

Аналогия из твоей области: это разница между «подать команды на изменение регистров» и «описать желаемую конфигурацию, драйвер сам приведёт железо в это состояние». Или между ручной отрисовкой дельт и полным перерасчётом кадра с последующим diff.

Цена — накладные расходы на сравнение деревьев. Выигрыш — количество состояний перестаёт быть твоей проблемой.

## 14.2 Компонент

```tsx
function Greeting({ name }: { name: string }) {
  return <h1>Привет, {name}</h1>;
}
```

Формально: функция, принимающая объект props и возвращающая описание UI.

Три требования:

**1. Имя с большой буквы.** `<greeting />` React считает HTML-тегом, `<Greeting />` — компонентом. Это не стиль, это правило разбора JSX.

**2. Чистота.** Одинаковые props → одинаковый результат. Во время рендера нельзя: менять props или внешние переменные, обращаться к DOM, делать запросы, читать `Date.now()` или `Math.random()` для результата рендера.

**3. Один корневой элемент.** Либо обёртка, либо фрагмент:
```jsx
return <>
  <Header />
  <Main />
</>;
```

**Почему чистота обязательна.** React оставляет за собой право вызвать компонент лишний раз, вызвать и выбросить результат, вызвать в другом порядке, вызвать в фоне для подготовки. В StrictMode он намеренно вызывает каждый компонент дважды в разработке — чтобы побочные эффекты вылезли сразу. Если компонент нечистый, поведение становится непредсказуемым.

## 14.3 JSX — это вызовы функций

JSX не шаблонизатор. Это синтаксический сахар, который компилятор превращает в вызовы:

```jsx
<button className="primary" onClick={handle}>Пуск</button>
```
превращается в
```js
jsx('button', { className: 'primary', onClick: handle, children: 'Пуск' })
```

Результат — обычный объект:
```js
{ type: 'button', props: { className: 'primary', children: 'Пуск' }, ... }
```

Это **описание** элемента, а не сам элемент DOM. Лёгкий объект, который React сравнит с предыдущим и решит, что менять.

Практические следствия:

**JSX — выражение.** Можно класть в переменные, возвращать из функций, складывать в массивы:
```jsx
const items = data.map(d => <Item key={d.id} {...d} />);
const content = isReady ? <Chart /> : <Spinner />;
```

**Внутри `{}` — любое JS-выражение**, но не инструкция:
```jsx
{count > 0 && <Badge n={count} />}       // ✅ выражение
{items.map(renderItem)}                   // ✅
{if (x) {...}}                            // ❌ инструкция
```

**Условия пишутся выражениями:**
```jsx
{isLoading ? <Spinner /> : <Content />}
{error && <Error msg={error} />}
{items.length === 0 && <Empty />}
```

Ловушка с `&&` и числами:
```jsx
{items.length && <List />}     // при 0 отрендерит "0" на странице!
{items.length > 0 && <List />} // ✅
```
Причина: `0` ложное, `&&` возвращает его, а React рендерит числа как текст. `false`, `null` и `undefined` не рендерятся, а `0` рендерится.

## 14.4 Отличия JSX от HTML

```jsx
<div className="box" />           // не class — class зарезервировано в JS
<label htmlFor="id" />            // не for
<input onChange={f} />            // camelCase события
<div style={{ marginTop: 8 }} />  // объект, не строка; camelCase свойства
<br />                            // самозакрытие обязательно
<div tabIndex={0} />              // числа в фигурных скобках
```

`style` принимает объект — двойные скобки это `{` JSX плюс `{` объекта, не особый синтаксис.

## 14.5 Props

Props **иммутабельны**. Компонент не может менять то, что ему передали:
```jsx
function Bad({ items }) {
  items.push(newItem);       // ❌ мутация чужих данных
}
```

Передача данных вниз, событий — вверх. Однонаправленный поток (урок 17).

**Деструктуризация в параметрах** — идиома (урок 04):
```tsx
function Button({ label, onClick, disabled = false }: ButtonProps) {}
```

**`children`** — особый props, всё между тегами:
```jsx
<Card><p>Текст</p></Card>
// внутри Card: props.children === <p>Текст</p>
```

**Проброс props** через spread — осторожно, легко передать лишнее:
```jsx
<Input {...rest} />
```

## 14.6 Композиция вместо конфигурации

Типичная ошибка новичка — раздувать props флагами:
```jsx
<Panel title="FFT" showHeader hasBorder icon="wave" collapsible />
```

Лучше — передавать содержимое:
```jsx
<Panel>
  <Panel.Header><Icon name="wave" /> FFT</Panel.Header>
  <Panel.Body><Controls /></Panel.Body>
</Panel>
```

Props как слоты — гибче любого набора флагов. Разберём подробно в уроке 18.

## 14.7 Что происходит при рендере

Три фазы:

1. **Trigger** — что-то запустило рендер: первый монтаж или изменение состояния
2. **Render** — React вызывает функции компонентов, получает дерево описаний, сравнивает с предыдущим
3. **Commit** — применяет минимальные изменения к реальному DOM

Фаза render может быть прервана, отменена, выполнена дважды. Фаза commit — синхронная и однократная. Отсюда все правила чистоты: побочные эффекты в render недопустимы, потому что render не гарантирован.

Детально реконсиляцию разберём в уроке 15.

---

# Часть 2. Проработка

## Задача. Создание проекта и первые компоненты

```bash
npm create vite@latest dsp-panel -- --template react-ts
cd dsp-panel
npm install
npm run dev
```

Приведи `tsconfig.json` к виду из урока 12. Добавь скрипт `"typecheck": "tsc --noEmit"`.

Удали из `src/` всё лишнее: `App.css`, логотипы, содержимое `App.tsx`.

**Типы — переносим из блока TypeScript:**
```ts
// src/types.ts
export const WINDOWS = {
  hann:     { label: 'Ханна',      alpha: 0.5  },
  hamming:  { label: 'Хэмминга',   alpha: 0.54 },
  blackman: { label: 'Блэкмана',   alpha: 0.42 },
  rect:     { label: 'Прямоугол.', alpha: 1    },
} as const satisfies Record<string, { label: string; alpha: number }>;

export type WindowFn = keyof typeof WINDOWS;

export const FFT_SIZES = [256, 512, 1024, 2048, 4096] as const;
export type FftSize = typeof FFT_SIZES[number];

export type FftConfig = {
  size: FftSize;
  window: WindowFn;
  overlap: number;
};

export type Analysis =
  | { status: 'idle' }
  | { status: 'running'; progress: number }
  | { status: 'done'; bins: Float32Array; elapsedMs: number }
  | { status: 'failed'; reason: string };
```

**Первый компонент — чистое отображение состояния:**
```tsx
// src/StatusLine.tsx
import type { Analysis } from './types';

export function StatusLine({ analysis }: { analysis: Analysis }) {
  switch (analysis.status) {
    case 'idle':
      return <span className="status">Готов к запуску</span>;
    case 'running':
      return <span className="status busy">
        Обработка {Math.round(analysis.progress * 100)}%
      </span>;
    case 'done':
      return <span className="status ok">
        {analysis.bins.length} бинов за {analysis.elapsedMs} мс
      </span>;
    case 'failed':
      return <span className="status err">Ошибка: {analysis.reason}</span>;
  }
}
```

Обрати внимание: это **тот же `switch`**, что был в уроке 08. Размеченное объединение и React стыкуются напрямую — в каждой ветке доступны только поля этого варианта. `analysis.bins` в ветке `'failed'` не скомпилируется.

Компилятор здесь работает как проверка полноты UI: добавишь состояние — он покажет, что для него нет отображения.

**Второй компонент — таблица параметров, чистая функция от props:**
```tsx
// src/ConfigView.tsx
import { WINDOWS, type FftConfig } from './types';

type Props = { config: FftConfig };

export function ConfigView({ config }: Props) {
  return (
    <dl className="config">
      <dt>Размер FFT</dt>
      <dd>{config.size}</dd>

      <dt>Окно</dt>
      <dd>{WINDOWS[config.window].label}</dd>

      <dt>Перекрытие</dt>
      <dd>{Math.round(config.overlap * 100)}%</dd>

      <dt>Разрешение</dt>
      <dd>{(44100 / config.size).toFixed(2)} Гц/бин</dd>
    </dl>
  );
}
```

`WINDOWS[config.window].label` типизирован полностью: `config.window` это union из четырёх литералов, `WINDOWS` имеет ровно эти ключи. Опечатка невозможна, автодополнение работает.

Последняя строка — вычисление прямо в рендере. Это правильно: производные данные считаются при отрисовке, а не хранятся в состоянии. Правило, к которому вернёмся в уроке 15.

**Сборка:**
```tsx
// src/App.tsx
import { StatusLine } from './StatusLine';
import { ConfigView } from './ConfigView';
import type { Analysis, FftConfig } from './types';

const config: FftConfig = { size: 1024, window: 'hann', overlap: 0.5 };
const analysis: Analysis = { status: 'idle' };

export default function App() {
  return (
    <main>
      <h1>DSP-панель</h1>
      <ConfigView config={config} />
      <StatusLine analysis={analysis} />
    </main>
  );
}
```

Пока всё статично — состояния нет, менять нечего. Это следующий урок.

**Поэкспериментируй.** Меняй значения `config` и `analysis` прямо в коде и смотри на hot reload. Убедись, что UI полностью определяется данными и больше ничем.

---

# Часть 3. Домашка

В проекте `dsp-panel`.

**1.** Компонент `WindowSelect` — выпадающий список окон, построенный из `WINDOWS`. Список не хардкодить, генерировать из объекта. Пока без обработчика, только отображение.

**2.** `ProgressBar({ value }: { value: number })` — полоса прогресса на `<div>` с шириной через `style`. Значение вне `[0,1]` должно ограничиваться.

**3.** Найди и объясни три ошибки:
```tsx
function List({ items }) {
  items.sort();
  return <ul>
    {items.length && items.map(i => <li>{i}</li>)}
  </ul>;
}
```

**4.** Почему это не работает и как исправить?
```tsx
function Toggle({ on }) {
  return <div class="toggle" style="color: red">{on}</div>;
}
```
Учти: `on` — булево.

**5.** Компонент `Field` с типизированными props: `label`, `value`, `unit?`. Отрисовывает подпись, значение и единицу измерения. Затем перепиши `ConfigView` через него — убедись, что дублирование ушло.

**6.** Разбери, во что превращается этот JSX. Напиши вручную эквивалент через вызовы `jsx()`:
```jsx
<Panel title="FFT">
  <Field label="Размер" value={1024} />
  {isReady && <Chart data={bins} />}
</Panel>
```

**7.** На понимание чистоты. Что сломается в StrictMode и почему?
```tsx
let renderCount = 0;
function Counter() {
  renderCount++;
  return <div>Отрисовок: {renderCount}</div>;
}
```
