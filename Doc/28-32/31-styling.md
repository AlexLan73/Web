# Урок 31. Стили: Tailwind или CSS Modules

Короткий прикладной урок. Главное — выбрать одно и не смешивать.

---

# Часть 1. Теория

## 31.1 Проблема глобального CSS

Обычный `.css` файл — глобальное пространство имён. Класс `.panel` в двух файлах конфликтует, порядок импортов влияет на результат, удалить старый стиль страшно — неизвестно, кто им пользуется.

Исторические решения: BEM (соглашение об именовании), CSS-in-JS (styled-components), CSS Modules (изоляция сборщиком), утилитарные классы (Tailwind).

Сейчас живых два: **CSS Modules** и **Tailwind**. CSS-in-JS уходит — он платит рантаймом за то, что теперь решается на этапе сборки.

## 31.2 CSS Modules

Работают в Vite из коробки, ничего ставить не нужно.

```css
/* Panel.module.css */
.panel {
  border: 1px solid var(--border);
  border-radius: 8px;
}

.header {
  display: flex;
  gap: 8px;
  font-weight: 600;
}

.collapsed .header { opacity: 0.6; }
```

```tsx
import styles from './Panel.module.css';

<section className={styles.panel}>
  <header className={styles.header}>...</header>
</section>
```

Сборщик генерирует уникальные имена (`_panel_1a2b3`). Конфликтов нет по построению.

**Плюсы:** обычный CSS со всеми возможностями, изоляция, ноль рантайма, файлы стилей рядом с компонентом.

**Минусы:** два файла на компонент, придумывание имён, склейка классов вручную.

**Типизация.** По умолчанию `styles` имеет тип `Record<string, string>` — опечатка даёт `undefined`. Лечится плагином:
```bash
npm i -D typed-css-modules
```
или в Vite 5+:
```ts
css: { modules: { localsConvention: 'camelCaseOnly' } }
```
плюс генерация `.d.ts`. Стоит настроить — иначе теряется единственное, ради чего мы всё это типизируем.

**Условные классы:**
```tsx
className={[styles.panel, collapsed && styles.collapsed].filter(Boolean).join(' ')}
```
Многословно. Ставь `clsx`:
```bash
npm i clsx
```
```tsx
import clsx from 'clsx';
className={clsx(styles.panel, collapsed && styles.collapsed)}
```

## 31.3 Tailwind

```bash
npm i -D tailwindcss @tailwindcss/vite
```

```ts
// vite.config.ts
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({ plugins: [react(), tailwindcss()] });
```

```css
/* src/index.css */
@import "tailwindcss";
```

Начиная с версии 4 конфиг в JS не обязателен — темизация делается через CSS-переменные:
```css
@theme {
  --color-brand: #4ade80;
  --font-mono: 'JetBrains Mono', monospace;
}
```

```tsx
<section className="rounded-lg border border-slate-700 bg-slate-900 p-4">
  <header className="flex items-center gap-2 font-semibold">...</header>
</section>
```

**Плюсы:** имена придумывать не надо, всё в одном файле, единая шкала отступов и цветов, мёртвых стилей не бывает, удаление компонента удаляет его стили.

**Минусы:** разметка становится шумной, нужно выучить систему имён, длинные строки классов.

**Условные классы** — тот же `clsx`, но с `tailwind-merge` для разрешения конфликтов:
```bash
npm i clsx tailwind-merge
```
```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
```
`twMerge` убирает конфликтующие утилиты: `cn('p-2', 'p-4')` даёт `p-4`, а не оба. Критично для компонентов, принимающих `className` снаружи.

**Против шума в разметке** — выноси варианты в объект:
```tsx
const variants = {
  primary: 'bg-emerald-600 hover:bg-emerald-500 text-white',
  ghost: 'bg-transparent hover:bg-slate-800 text-slate-300',
  danger: 'bg-red-600 hover:bg-red-500 text-white',
} satisfies Record<Variant, string>;

<button className={cn('rounded px-3 py-1.5', variants[variant], className)} />
```
`satisfies` (урок 12) гарантирует, что описаны все варианты.

Для сложных случаев — `class-variance-authority` (cva), библиотека вариантов с типами.

## 31.4 Что выбрать

| | CSS Modules | Tailwind |
|---|---|---|
| Порог входа | нулевой, если знаешь CSS | надо выучить имена |
| Скорость разработки | ниже | выше после привыкания |
| Читаемость разметки | лучше | хуже |
| Читаемость стилей | хуже (прыгать между файлами) | лучше (всё видно сразу) |
| Единообразие | на дисциплине | встроено |
| Сложные селекторы, анимации | естественно | неудобно, нужен CSS |

**Практический совет.** Для инженерных панелей и внутренних инструментов Tailwind обычно выигрывает: интерфейс типовой, дизайн-система не нужна, скорость важнее эстетики разметки.

Если основная работа — сложная графика с анимациями и нестандартными селекторами, CSS Modules удобнее.

**Смешивать не надо.** Гибрид даёт худшее от обоих: и файлы стилей, и шум в разметке, и вопрос «где искать» на каждом компоненте.

## 31.5 Темы через CSS-переменные

Работает одинаково с обоими подходами:

```css
:root {
  --bg: #0f172a;
  --fg: #e2e8f0;
  --accent: #4ade80;
  --border: #334155;
}

[data-theme='light'] {
  --bg: #ffffff;
  --fg: #0f172a;
  --border: #cbd5e1;
}
```

```tsx
// применение темы из стора урока 29
function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useSettings(s => s.theme);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  return <>{children}</>;
}
```

Законный эффект по критерию урока 19: синхронизация React-состояния с DOM за пределами дерева компонентов.

Переключение темы через атрибут, а не через классы на каждом элементе — браузер пересчитывает переменные сам, без перерисовки React.

## 31.6 Что не надо стилизовать вручную

**Фокус.** `outline: none` без замены — распространённая ошибка доступности. Пользователи клавиатуры перестают понимать, где находятся. Если убираешь — обязательно дай `:focus-visible` стиль.

**Отключённое состояние.** `disabled` — нативный атрибут, стилизуй через `:disabled`, а не через класс. Иначе состояние и вид разъедутся.

**Скроллбары, выделение текста, курсоры** — переопределяй только при явной необходимости.

---

# Часть 2. Проработка

## Задача. Оформление панели на Tailwind

Беру Tailwind — для этого проекта он подходит лучше. Если предпочитаешь CSS Modules, разметка та же, классы переезжают в файлы.

```ts
// src/lib/cn.ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
```

```css
/* src/index.css */
@import "tailwindcss";

@theme {
  --color-surface: #0f172a;
  --color-surface-2: #1e293b;
  --color-line: #334155;
  --color-signal: #4ade80;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;
}

html[data-theme='light'] {
  --color-surface: #ffffff;
  --color-surface-2: #f1f5f9;
  --color-line: #cbd5e1;
  --color-signal: #059669;
}
```

**Кнопка с вариантами:**
```tsx
// src/ui/Button.tsx
import { cn } from '@/lib/cn';
import type { ComponentPropsWithoutRef, ReactNode } from 'react';

type Variant = 'primary' | 'ghost' | 'danger';
type Size = 'sm' | 'md';

const variants = {
  primary: 'bg-emerald-600 text-white hover:bg-emerald-500 active:bg-emerald-700',
  ghost: 'bg-transparent text-slate-300 hover:bg-slate-800',
  danger: 'bg-red-600 text-white hover:bg-red-500',
} satisfies Record<Variant, string>;

const sizes = {
  sm: 'px-2 py-1 text-xs',
  md: 'px-3 py-1.5 text-sm',
} satisfies Record<Size, string>;

type BaseProps = { variant?: Variant; size?: Size; loading?: boolean; icon?: ReactNode };

export type ButtonProps = BaseProps &
  Omit<ComponentPropsWithoutRef<'button'>, keyof BaseProps>;

export function Button({
  variant = 'primary', size = 'md', loading = false,
  icon, children, className, disabled, ...rest
}: ButtonProps) {
  return (
    <button
      className={cn(
        'inline-flex items-center gap-1.5 rounded font-medium transition-colors',
        'focus-visible:outline focus-visible:outline-2 focus-visible:outline-emerald-400',
        'disabled:cursor-not-allowed disabled:opacity-50',
        variants[variant],
        sizes[size],
        className,
      )}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Spinner className="size-3.5" /> : icon}
      {children}
    </button>
  );
}
```

**Разбор.**

**`className` последним в `cn`.** Порядок важен: `twMerge` оставляет последнее из конфликтующих, поэтому переданный снаружи класс побеждает внутренний. Без этого `<Button className="px-8">` не сработал бы.

**`disabled:opacity-50` вместо условного класса.** Состояние берётся из нативного атрибута — рассинхрон невозможен.

**`focus-visible`, а не `focus`.** Обводка появляется при навигации клавиатурой и не появляется при клике мышью. Именно то поведение, которое нужно.

**`satisfies Record<Variant, string>`** — забыл вариант, компилятор показал. Тот же приём, что для таблицы окон в уроке 12.

**Панель:**
```tsx
export function Panel({ title, actions, children, collapsed, onToggle }: PanelProps) {
  return (
    <section className="rounded-lg border border-[--color-line] bg-[--color-surface-2]">
      <header className="flex items-center gap-2 border-b border-[--color-line] px-3 py-2">
        {onToggle && (
          <button
            onClick={onToggle}
            className="text-slate-400 hover:text-slate-200"
            aria-expanded={!collapsed}
          >
            {collapsed ? '▸' : '▾'}
          </button>
        )}
        <h2 className="flex-1 text-sm font-semibold">{title}</h2>
        {actions && <div className="flex gap-1">{actions}</div>}
      </header>
      {!collapsed && <div className="p-3">{children}</div>}
    </section>
  );
}
```

`bg-[--color-surface-2]` — обращение к CSS-переменной. Тема меняется атрибутом на `<html>`, все панели перекрашиваются без единого рендера React.

**Раскладка:**
```tsx
export function Layout({ sidebar, children }: LayoutProps) {
  return (
    <div className="grid h-screen grid-cols-[280px_1fr] bg-[--color-surface] text-slate-200">
      <aside className="overflow-y-auto border-r border-[--color-line] p-3">
        {sidebar}
      </aside>
      <main className="overflow-y-auto p-4 flex flex-col gap-4">{children}</main>
    </div>
  );
}
```

**Таблица со строками одинаковой высоты** — важно для длинных списков:
```tsx
<tr className={cn(
  'h-8 cursor-pointer border-b border-[--color-line]/50 transition-colors',
  'hover:bg-slate-800/50',
  selected && 'bg-emerald-900/30 hover:bg-emerald-900/40',
)}>
```

**Числовые колонки — моноширинный шрифт и выравнивание вправо:**
```tsx
<td className="text-right font-mono tabular-nums">{peakHz.toFixed(1)}</td>
```
`tabular-nums` даёт цифрам одинаковую ширину — числа в столбце не пляшут при обновлении. Мелочь, которая заметно улучшает читаемость приборной панели.

**Canvas растягивается корректно:**
```tsx
<canvas
  ref={canvasRef}
  className="w-full rounded border border-[--color-line]"
  width={800}
  height={300}
/>
```
Атрибуты `width`/`height` — это разрешение буфера, CSS-размер — отображаемый размер. Они независимы. При растягивании через CSS картинка масштабируется и мылит; для чёткости надо синхронизировать размер буфера с реальным, учитывая `devicePixelRatio` — это в домашке.

---

# Часть 3. Домашка

**1.** Настрой Tailwind (или CSS Modules — но выбери одно). Оформи `Button`, `Panel`, `Field`, `Layout`. Проверь, что переданный снаружи `className` перекрывает внутренний.

**2.** Реализуй переключение темы: стор из урока 29, атрибут на `<html>`, CSS-переменные. Убедись, что при переключении React не перерисовывает дерево — проверь профайлером.

**3.** Почему без `twMerge` это не работает, и что получится?
```tsx
<Button className="px-8 bg-blue-600" />
```

**4.** Сделай `Field` с состояниями: обычное, с ошибкой, отключённое, обязательное. Ошибка должна быть заметна и без цвета (для дальтоников) — добавь иконку или начертание.

**5.** Резкость canvas. Синхронизируй размер буфера с CSS-размером и `devicePixelRatio`. Реализуй через `ResizeObserver` в эффекте. Сравни чёткость линии спектра до и после на экране с масштабированием.

**6.** Доступность. Пройди по приложению только клавиатурой: Tab, Enter, Escape, стрелки. Найди места, где фокус теряется или не виден. Исправь через `focus-visible` и `tabIndex`.

**7.** Собери прод-версию, посмотри размер CSS в `dist/`. Затем добавь десяток новых компонентов и пересобери — объясни, почему размер почти не вырос (для Tailwind) или вырос линейно (для CSS Modules).

**8.** Перепиши один компонент вторым способом — если делал на Tailwind, сделай CSS Modules, и наоборот. Сравни: количество строк, количество файлов, читаемость, время написания. Сформулируй, что выбрал бы для следующего проекта и почему.
