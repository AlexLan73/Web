# Урок 27. Роутинг

URL — это тоже состояние. Причём состояние, которое пользователь может сохранить в закладки, отправить коллеге и восстановить кнопкой «назад».

---

# Часть 1. Теория

## 27.1 Зачем роутер

SPA грузит одну HTML-страницу и меняет содержимое на клиенте. Без роутера получается приложение с одним URL: обновил страницу — вернулся в начало, кнопка «назад» закрывает вкладку, ссылкой поделиться нельзя.

Роутер связывает URL с тем, что отрисовано, и работает с `history` API браузера.

**Главный тезис урока:** часть состояния должна жить в URL, а не в `useState`. Это правило из урока 17, теперь с инструментом.

**Что кладут в URL:** текущая страница, выбранная сущность, фильтры, сортировка, поисковый запрос, номер страницы, открытая вкладка.

**Что не кладут:** черновики форм, состояние анимаций, развёрнутость деталей, данные с сервера.

Критерий простой: **если пользователь может захотеть вернуться к этому виду или показать его кому-то — это URL.**

## 27.2 React Router

Стандарт де-факто. Ставится:
```bash
npm i react-router-dom
```

```tsx
import { createBrowserRouter, RouterProvider } from 'react-router-dom';

const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Home /> },
      { path: 'runs', element: <RunList /> },
      { path: 'runs/:runId', element: <RunDetails /> },
      { path: 'settings', element: <Settings /> },
      { path: '*', element: <NotFound /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
```

**Вложенные маршруты** — родитель рисует общую раскладку, `<Outlet />` подставляет активного ребёнка:
```tsx
function Layout() {
  return (
    <>
      <nav><NavLink to="/runs">Прогоны</NavLink></nav>
      <main><Outlet /></main>
    </>
  );
}
```

**Навигация:**
```tsx
<Link to="/runs/42">Открыть</Link>
<NavLink to="/runs" className={({ isActive }) => isActive ? 'on' : ''}>
  Прогоны
</NavLink>

const navigate = useNavigate();
navigate('/runs/42');
navigate(-1);                          // назад
navigate('/runs', { replace: true });  // без записи в историю
```

**`<Link>` вместо `<a>`** — обычная ссылка перезагрузит страницу целиком, потеряв всё состояние приложения.

## 27.3 Параметры пути

```tsx
function RunDetails() {
  const { runId } = useParams();       // string | undefined
  if (!runId) return <NotFound />;
  ...
}
```

**Типизация слабая** — `useParams` возвращает `Record<string, string | undefined>`. Роутер не знает, какие параметры есть у текущего маршрута.

Варианты усиления:
```tsx
const { runId } = useParams<{ runId: string }>();   // всё равно | undefined
```

Честный подход — валидировать на входе:
```tsx
function useRunId(): string {
  const { runId } = useParams();
  if (!runId) throw new Error('runId обязателен');
  return runId;
}
```

Полная типобезопасность — у **TanStack Router**: там маршруты описываются объектами, параметры выводятся из пути через template literal types (тот самый `RouteParams` из домашки урока 11). Если типы важны, он лучше. React Router выбирают за распространённость и объём документации.

## 27.4 Query-параметры

Для фильтров и настроек вида:

```tsx
const [searchParams, setSearchParams] = useSearchParams();

const sort = searchParams.get('sort') ?? 'date';
const size = Number(searchParams.get('size') ?? 1024);

setSearchParams(prev => {
  prev.set('sort', 'peak');
  return prev;
});
```

`URLSearchParams` — стандартный браузерный API, всё строками.

**Типизированная обёртка** — стоит написать один раз:
```tsx
function useQueryParam<T extends string>(
  key: string,
  allowed: readonly T[],
  fallback: T,
): [T, (v: T) => void] {
  const [params, setParams] = useSearchParams();
  const raw = params.get(key);
  const value = allowed.includes(raw as T) ? (raw as T) : fallback;

  const set = useCallback((v: T) => {
    setParams(prev => {
      v === fallback ? prev.delete(key) : prev.set(key, v);
      return prev;
    }, { replace: true });
  }, [key, fallback, setParams]);

  return [value, set];
}
```

Использование выглядит как `useState`, но значение живёт в URL:
```tsx
const [sort, setSort] = useQueryParam('sort', ['date', 'peak', 'time'] as const, 'date');
```

**`replace: true`** для фильтров — иначе каждое нажатие галочки создаёт запись в истории, и кнопка «назад» перестаёт работать осмысленно.

**Удаление параметра при значении по умолчанию** держит URL чистым.

## 27.5 Ленивая загрузка маршрутов

Основное применение `lazy` из урока 26:

```tsx
const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      {
        path: 'analysis',
        lazy: async () => {
          const { Analysis } = await import('@/features/analysis');
          return { Component: Analysis };
        },
      },
    ],
  },
]);
```

Каждая страница — свой чанк. Пользователь, зашедший на главную, не грузит код настроек.

## 27.6 Границы ошибок

```tsx
{
  path: 'runs/:runId',
  element: <RunDetails />,
  errorElement: <ErrorPage />,
}
```

Ошибка при рендере поддерева перехватывается и показывает `errorElement` вместо белого экрана.

```tsx
function ErrorPage() {
  const error = useRouteError();
  return <div>
    <h1>Что-то сломалось</h1>
    <pre>{error instanceof Error ? error.message : String(error)}</pre>
  </div>;
}
```

`useRouteError` возвращает `unknown` — сужай через `instanceof` (урок 07).

**Границы ошибок не ловят:** ошибки в обработчиках событий, в асинхронном коде, в эффектах после первого рендера. Только ошибки во время рендера.

## 27.7 Защищённые маршруты

```tsx
function RequireAuth({ children }: { children: React.ReactNode }) {
  const user = useUser();
  const location = useLocation();

  if (!user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }
  return <>{children}</>;
}
```

`state` в навигации позволяет вернуть пользователя туда, откуда его увели. `replace` не оставляет защищённую страницу в истории.

---

# Часть 2. Проработка

## Задача. Состояние панели в URL

Разносим `dsp-panel` по маршрутам и переносим настройки вида в query.

```tsx
// src/app/router.tsx
import { createBrowserRouter, Navigate } from 'react-router-dom';
import { Layout } from './Layout';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    errorElement: <ErrorPage />,
    children: [
      { index: true, element: <Navigate to="/analysis" replace /> },
      {
        path: 'analysis',
        lazy: async () => {
          const { AnalysisPage } = await import('@/features/analysis');
          return { Component: AnalysisPage };
        },
      },
      {
        path: 'runs',
        lazy: async () => {
          const { RunsPage } = await import('@/features/runs');
          return { Component: RunsPage };
        },
      },
      {
        path: 'runs/:runId',
        lazy: async () => {
          const { RunDetailsPage } = await import('@/features/runs');
          return { Component: RunDetailsPage };
        },
      },
      { path: '*', element: <NotFound /> },
    ],
  },
]);
```

```tsx
// src/app/Layout.tsx
import { NavLink, Outlet } from 'react-router-dom';

export function Layout() {
  return (
    <div className="app">
      <nav className="app-nav">
        <NavLink to="/analysis" className={({ isActive }) => isActive ? 'on' : ''}>
          Анализ
        </NavLink>
        <NavLink to="/runs" className={({ isActive }) => isActive ? 'on' : ''}>
          Прогоны
        </NavLink>
      </nav>
      <main className="app-main"><Outlet /></main>
    </div>
  );
}
```

**Параметры FFT в URL.** Это спорное решение, поэтому разберу подробно.

За: ссылку на конкретную конфигурацию можно отправить коллеге — «посмотри, что получается при 4096 с окном Блэкмана». Для инженерного инструмента это осмысленно.

Против: каждое движение ползунка меняет URL. Решается `replace: true` и дебаунсом.

```tsx
// src/features/analysis/hooks/useConfigFromUrl.ts
import { useSearchParams } from 'react-router-dom';
import { useCallback, useMemo } from 'react';
import { FFT_SIZES, WINDOWS, type FftConfig, type FftSize, type WindowFn } from '@/types';
import { DEFAULT_CONFIG } from '../state/panel';

export function useConfigFromUrl(): [FftConfig, (p: Partial<FftConfig>) => void] {
  const [params, setParams] = useSearchParams();

  const config = useMemo<FftConfig>(() => {
    const rawSize = Number(params.get('size'));
    const size = (FFT_SIZES as readonly number[]).includes(rawSize)
      ? (rawSize as FftSize)
      : DEFAULT_CONFIG.size;

    const rawWindow = params.get('window');
    const window = rawWindow && rawWindow in WINDOWS
      ? (rawWindow as WindowFn)
      : DEFAULT_CONFIG.window;

    const rawOverlap = Number(params.get('overlap'));
    const overlap = Number.isFinite(rawOverlap) && rawOverlap >= 0 && rawOverlap < 1
      ? rawOverlap
      : DEFAULT_CONFIG.overlap;

    return { size, window, overlap };
  }, [params]);

  const patch = useCallback((p: Partial<FftConfig>) => {
    setParams(prev => {
      const next = { ...config, ...p };
      // не пишем в URL то, что совпадает с дефолтом
      for (const key of ['size', 'window', 'overlap'] as const) {
        String(next[key]) === String(DEFAULT_CONFIG[key])
          ? prev.delete(key)
          : prev.set(key, String(next[key]));
      }
      return prev;
    }, { replace: true });
  }, [config, setParams]);

  return [config, patch];
}
```

**Разбор.**

**Валидация обязательна.** URL пришёл извне — это ровно та же граница с внешним миром, что и данные с сервера (урок 07). Пользователь может вписать `?size=банан`. Невалидное значение молча заменяется дефолтом; альтернатива — показать ошибку, но для настроек вида это перебор.

**`(FFT_SIZES as readonly number[]).includes(rawSize)`** — приведение нужно, потому что `FFT_SIZES` это кортеж литералов, и `includes` требует аргумент того же типа. Ищем произвольное число — приходится расширить тип массива. Это одно из известных неудобств `as const`.

**`rawWindow in WINDOWS`** сужает `string` до ключа объекта — сужение через `in` из урока 07 работает и здесь.

**`useMemo` по `params`** — не оптимизация, а стабильность ссылки. Без него `config` был бы новым объектом на каждом рендере, и все эффекты, зависящие от него, срабатывали бы постоянно (урок 19).

**Дефолты не пишутся в URL.** Чистая ссылка `/analysis` вместо `/analysis?size=1024&window=hann&overlap=0.5`. Приём стоит применять всегда.

**Сборка страницы:**
```tsx
// src/features/analysis/AnalysisPage.tsx
export function AnalysisPage() {
  const [config, patchConfig] = useConfigFromUrl();
  const { state, dispatch } = usePanel(config);
  const isBusy = state.analysis.status === 'running';

  return (
    <Layout sidebar={
      <Panel title="Параметры">
        <ConfigEditor value={config} onChange={patchConfig} disabled={isBusy} />
      </Panel>
    }>
      <Panel title="Результат" actions={<StatusLine analysis={state.analysis} />}>
        <Button onClick={() => dispatch({
          type: isBusy ? 'run/cancel' : 'run/start', config,
        })}>
          {isBusy ? 'Отменить' : 'Запустить'}
        </Button>
        <SpectrumCanvas bins={state.analysis.status === 'done' ? state.analysis.bins : null} />
      </Panel>
    </Layout>
  );
}
```

Конфиг переехал из редьюсера в URL. Редьюсер теперь отвечает только за ход расчёта — стал проще. Это типичный эффект от правильного размещения состояния.

**Список прогонов с фильтрами в URL:**
```tsx
export function RunsPage() {
  const { runs } = useRuns();
  const [sort, setSort] = useQueryParam('sort', ['date', 'peak', 'time'] as const, 'date');
  const [q, setQ] = useSearchParams();
  const query = q.get('q') ?? '';

  const visible = useMemo(() => {
    const filtered = query
      ? runs.filter(r => r.label.toLowerCase().includes(query.toLowerCase()))
      : runs;
    return [...filtered].sort(comparators[sort]);
  }, [runs, query, sort]);

  return (
    <>
      <input value={query} onChange={e => setQ(p => {
        e.target.value ? p.set('q', e.target.value) : p.delete('q');
        return p;
      }, { replace: true })} />

      <Select value={sort} options={['date', 'peak', 'time'] as const} onChange={setSort} />

      <DataTable
        rows={visible}
        getKey={r => r.id}
        onRowClick={r => navigate(`/runs/${r.id}`)}
        columns={[...]}
      />
    </>
  );
}
```

**Проверь результат.** Отфильтруй, отсортируй, скопируй URL, открой в новой вкладке — вид должен восстановиться полностью. Понажимай «назад» — состояния фильтров не должны засорять историю (спасибо `replace`).

---

# Часть 3. Домашка

**1.** Настрой роутер с четырьмя маршрутами, вложенной раскладкой и страницей 404. Проверь, что прямой переход по адресу работает после `npm run build && npm run preview`.

**2.** Почему при обновлении страницы на `/runs/42` в проде может быть 404, а в dev всё работает? Разберись и объясни, что настраивать на сервере.

**3.** Реализуй `useQueryParam` из 27.4 полностью. Затем расширь до `useQueryState<T>` с сериализацией — чтобы работали числа и булевы значения, а не только строки из union.

**4.** Типизация параметров. Напиши обёртку `useTypedParams<T extends string>(...keys: T[])`, которая возвращает `Record<T, string>` и бросает осмысленную ошибку при отсутствии параметра.

**5.** Защищённый маршрут: страница настроек доступна только при включённом «режиме эксперта» (флаг в `localStorage`). Реализуй редирект с возвратом на исходную страницу после включения.

**6.** Ленивая загрузка всех страниц. Собери проект, посмотри в `dist/assets/` — сколько чанков и какого размера. Сравни размер начальной загрузки до и после.

**7.** Границы ошибок. Сломай `RunDetails` намеренно (обращение к полю `undefined`), убедись, что показывается `errorElement`, а не белый экран. Затем сломай в обработчике клика — объясни, почему теперь не сработало.

**8.** Архитектурное. Список из урока 25 хранит состояние в редьюсере, фильтры — в URL, данные — в `localStorage`. Нарисуй, что где живёт и почему, и найди хотя бы одно место, где сейчас дублирование.
