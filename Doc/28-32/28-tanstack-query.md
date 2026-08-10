# Урок 28. TanStack Query — серверные данные

В уроке 19 мы выяснили, что правильная загрузка данных вручную — это гонки, отмена, кеш, повторы, состояния загрузки и инвалидация. Всё это уже написано.

---

# Часть 1. Теория

## 28.1 Главная идея

**Серверные данные — не состояние приложения, а кеш.**

Разница принципиальная. Обычное состояние ты создаёшь и владеешь им. Серверные данные тебе не принадлежат: настоящее значение лежит на сервере, у тебя копия, которая устаревает в любой момент — кто-то другой мог их изменить.

Отсюда всё остальное: устаревание, фоновое обновление, инвалидация, повторные попытки. Держать это в `useState` — значит писать кеш вручную, обычно плохо.

Разделяй два вида состояния:
- **серверное** — приходит извне, может устареть → Query
- **клиентское** — твоё, живёт в браузере → `useState`, `useReducer`, Zustand (урок 29)

Смешивание — самая частая архитектурная ошибка во фронтенде.

## 28.2 Установка

```bash
npm i @tanstack/react-query
npm i -D @tanstack/react-query-devtools
```

```tsx
// src/app/main.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,          // 30 сек считаем свежими
      retry: 2,
      refetchOnWindowFocus: false,
    },
  },
});

<QueryClientProvider client={queryClient}>
  <RouterProvider router={router} />
  <ReactQueryDevtools />
</QueryClientProvider>
```

**`staleTime` по умолчанию — 0**, то есть данные считаются устаревшими сразу. Для большинства приложений это агрессивно. Ставь осознанно.

## 28.3 `useQuery`

```tsx
const { data, isPending, isError, error, refetch } = useQuery({
  queryKey: ['runs'],
  queryFn: fetchRuns,
});
```

**`queryKey`** — идентификатор в кеше. Массив, сравнивается структурно. Всё, от чего зависит запрос, должно быть в ключе:

```tsx
useQuery({
  queryKey: ['runs', { sort, filter }],
  queryFn: () => fetchRuns({ sort, filter }),
});
```

Изменился ключ — Query считает это другими данными и загружает заново, показывая закешированное для старого ключа, пока новое грузится.

**`queryFn` должна бросать при ошибке.** `fetch` не бросает на 404 или 500 — проверяй сам:
```ts
async function fetchRuns(): Promise<Run[]> {
  const res = await fetch('/api/runs');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}
```

**Отмена** — `queryFn` получает `signal`:
```ts
queryFn: ({ signal }) => fetch('/api/runs', { signal }).then(r => r.json())
```
Гонка из урока 19 решается сама.

## 28.4 Состояния

```tsx
const q = useQuery({ queryKey: ['runs'], queryFn: fetchRuns });

q.status;        // 'pending' | 'error' | 'success'
q.fetchStatus;   // 'fetching' | 'paused' | 'idle'
q.isPending;     // нет данных вообще
q.isFetching;    // запрос идёт (в том числе фоновый при наличии данных)
q.isStale;
```

**Два измерения, а не одно.** `status` — есть ли данные. `fetchStatus` — идёт ли сейчас запрос. Они независимы: можно иметь данные (`success`) и одновременно фоново обновлять их (`fetching`).

Отсюда правильный рендер:
```tsx
if (q.isPending) return <Spinner />;              // данных нет вообще
if (q.isError) return <Error error={q.error} />;
return (
  <>
    {q.isFetching && <RefreshIndicator />}         // ненавязчиво, поверх данных
    <RunList runs={q.data} />                      {/* data: Run[], не undefined */}
  </>
);
```

**Сужение типа работает.** После проверок `isPending` и `isError` компилятор знает, что `data` определена. Внутри Query — то самое размеченное объединение из урока 08.

## 28.5 Мутации

```tsx
const queryClient = useQueryClient();

const saveRun = useMutation({
  mutationFn: (run: CreateRun) =>
    fetch('/api/runs', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(run),
    }).then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json() as Promise<Run>;
    }),

  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['runs'] });
  },
});

saveRun.mutate(newRun);
saveRun.isPending;
```

**`invalidateQueries`** помечает кеш устаревшим — активные запросы перезагрузятся. Это основной способ синхронизации после изменения.

**`mutate` против `mutateAsync`:** первый не бросает, ошибка попадает в `mutation.error`. Второй возвращает промис и бросает — нужен, когда после мутации идёт другая логика.

**Оптимистичное обновление** — показать результат до ответа сервера:
```tsx
const remove = useMutation({
  mutationFn: (id: string) => fetch(`/api/runs/${id}`, { method: 'DELETE' }),

  onMutate: async (id) => {
    await queryClient.cancelQueries({ queryKey: ['runs'] });
    const prev = queryClient.getQueryData<Run[]>(['runs']);
    queryClient.setQueryData<Run[]>(['runs'], old =>
      old?.filter(r => r.id !== id) ?? []);
    return { prev };                                  // контекст для отката
  },

  onError: (_err, _id, context) => {
    if (context?.prev) queryClient.setQueryData(['runs'], context.prev);
  },

  onSettled: () => queryClient.invalidateQueries({ queryKey: ['runs'] }),
});
```

Три шага: отменить текущие запросы (иначе они перезапишут наше изменение), сохранить снимок для отката, применить изменение локально. При ошибке — вернуть снимок. В конце — синхронизироваться с сервером в любом случае.

## 28.6 Организация ключей

При десятке запросов ключи расползаются. Фабрика решает:

```ts
// src/features/runs/api/keys.ts
export const runKeys = {
  all: ['runs'] as const,
  lists: () => [...runKeys.all, 'list'] as const,
  list: (filters: RunFilters) => [...runKeys.lists(), filters] as const,
  details: () => [...runKeys.all, 'detail'] as const,
  detail: (id: string) => [...runKeys.details(), id] as const,
};
```

Иерархия даёт частичную инвалидацию: `invalidateQueries({ queryKey: runKeys.lists() })` сбросит все списки, не трогая детали. `runKeys.all` — вообще всё про прогоны.

`as const` (урок 12) сохраняет литеральные типы — ключи типизированы точно.

## 28.7 Ещё несколько возможностей

**Зависимые запросы:**
```tsx
const { data: run } = useQuery({ queryKey: ['run', id], queryFn: () => fetchRun(id) });
const { data: signal } = useQuery({
  queryKey: ['signal', run?.sourceId],
  queryFn: () => fetchSignal(run!.sourceId),
  enabled: !!run?.sourceId,          // не запускать, пока нет sourceId
});
```

**Предзагрузка** — при наведении на строку списка:
```tsx
onMouseEnter={() => queryClient.prefetchQuery({
  queryKey: runKeys.detail(id),
  queryFn: () => fetchRun(id),
})}
```

**`placeholderData`** для пагинации — показывать старую страницу, пока грузится новая:
```tsx
placeholderData: keepPreviousData
```
Без него список мигает в пустое состояние при каждом переключении.

## 28.8 Типизация

```tsx
function useRuns(filters: RunFilters) {
  return useQuery({
    queryKey: runKeys.list(filters),
    queryFn: ({ signal }) => fetchRuns(filters, signal),
  });
}
```

Тип `data` выводится из возврата `queryFn`. Явно указывать не нужно — и не стоит: аннотация `useQuery<Run[]>` может разойтись с реальностью, а вывод не может.

**Валидация ответа обязательна.** `res.json()` возвращает `any` — типы врут:
```ts
const raw: unknown = await res.json();
return RunSchema.array().parse(raw);      // Zod, урок 30
```
Без валидации ты просто заявил компилятору, что сервер прислал правильное. Это `as` в чистом виде.

---

# Часть 2. Проработка

## Задача. Прогоны на сервере

Переносим `useRuns` из `localStorage` (урок 21) на серверный API.

```ts
// src/features/runs/api/runs.ts
import type { Run, CreateRun, RunFilters } from '../types';

const BASE = import.meta.env.VITE_API_URL;

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new ApiError(res.status, text || res.statusText);
  }

  return res.json() as Promise<T>;
}

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export const runsApi = {
  list: (filters: RunFilters, signal?: AbortSignal) =>
    request<Run[]>(`/runs?${new URLSearchParams(
      Object.entries(filters).map(([k, v]) => [k, String(v)])
    )}`, { signal }),

  get: (id: string, signal?: AbortSignal) =>
    request<Run>(`/runs/${id}`, { signal }),

  create: (run: CreateRun) =>
    request<Run>('/runs', { method: 'POST', body: JSON.stringify(run) }),

  remove: (id: string) =>
    request<void>(`/runs/${id}`, { method: 'DELETE' }),
};
```

**Свой класс ошибки** позволяет различать 404 и 500 в обработчиках — обычный `Error` этого не даёт. Проверка через `instanceof ApiError` (урок 07).

**Хуки:**
```ts
// src/features/runs/api/queries.ts
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { runsApi, ApiError } from './runs';
import { runKeys } from './keys';

export function useRuns(filters: RunFilters) {
  return useQuery({
    queryKey: runKeys.list(filters),
    queryFn: ({ signal }) => runsApi.list(filters, signal),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });
}

export function useRun(id: string | undefined) {
  return useQuery({
    queryKey: runKeys.detail(id ?? ''),
    queryFn: ({ signal }) => runsApi.get(id!, signal),
    enabled: !!id,
    retry: (count, error) => {
      if (error instanceof ApiError && error.status === 404) return false;
      return count < 2;
    },
  });
}

export function useCreateRun() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: runsApi.create,
    onSuccess: (created) => {
      qc.setQueryData(runKeys.detail(created.id), created);   // кладём сразу
      qc.invalidateQueries({ queryKey: runKeys.lists() });     // списки перезагрузить
    },
  });
}

export function useDeleteRun() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: runsApi.remove,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: runKeys.lists() });
      const snapshots = qc.getQueriesData<Run[]>({ queryKey: runKeys.lists() });
      for (const [key] of snapshots) {
        qc.setQueryData<Run[]>(key, old => old?.filter(r => r.id !== id) ?? []);
      }
      return { snapshots };
    },
    onError: (_e, _id, ctx) => {
      ctx?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSettled: () => qc.invalidateQueries({ queryKey: runKeys.lists() }),
  });
}
```

**Разбор.**

**`retry` с проверкой на 404.** Повторять запрос несуществующего ресурса бессмысленно — три попытки просто задержат показ ошибки. Различие возможно благодаря своему классу ошибки.

**`enabled: !!id`** — запрос не стартует, пока нет идентификатора. Нужно для маршрута с параметром, который может быть `undefined` (урок 27).

**`setQueryData` после создания** — сервер вернул созданный объект, кладём его в кеш деталей. Если пользователь сразу перейдёт на страницу этого прогона, данные уже там, спиннера не будет.

**Оптимистичное удаление по всем спискам.** Списков может быть несколько (разные фильтры), поэтому `getQueriesData` с префиксным ключом, а не `getQueryData` с одним.

**Использование:**
```tsx
// src/features/runs/RunsPage.tsx
export function RunsPage() {
  const [sort] = useQueryParam('sort', ['date', 'peak'] as const, 'date');
  const [q] = useSearchParams();
  const filters = { sort, query: q.get('q') ?? '' };

  const runs = useRuns(filters);
  const del = useDeleteRun();

  if (runs.isPending) return <Spinner />;
  if (runs.isError) return <ErrorBox error={runs.error} onRetry={runs.refetch} />;

  return (
    <>
      {runs.isFetching && <div className="refreshing">Обновление…</div>}
      <DataTable
        rows={runs.data}
        getKey={r => r.id}
        columns={[
          { key: 'label', header: 'Название' },
          { key: 'peakHz', header: 'Пик', render: hz => `${hz.toFixed(1)} Гц` },
        ]}
        onRowClick={r => navigate(`/runs/${r.id}`)}
      />
      {del.isError && <Toast>Не удалось удалить: {del.error.message}</Toast>}
    </>
  );
}
```

**Что исчезло из кода.** Ни одного `useEffect`, ни одного `useState` для данных, ни одного `AbortController`, ни одной проверки на гонку, ни одного ручного состояния загрузки. Всё это внутри Query.

**Сравни с уроком 19.** Там ровно на эту задачу уходило тридцать строк с флагом актуальности и обработкой отмены — и всё равно без кеша, без повторов и без фонового обновления.

**Что осталось клиентским.** Конфигурация FFT — в URL (урок 27). Ход текущего расчёта — в редьюсере (урок 25), потому что расчёт идёт локально в воркере. Прогоны — в Query. Три вида состояния, три инструмента, границы чёткие.

**Проверь.** Открой devtools Query (значок в углу): видно кеш, статусы, время устаревания. Удали прогон — строка исчезнет мгновенно, до ответа сервера. Отключи сеть и повтори — строка исчезнет и вернётся с ошибкой. Это откат из `onError`.

---

# Часть 3. Домашка

**1.** Настрой Query, замени `useRuns` на серверную версию. Бэкенд можно заменить `json-server` или мок-обработчиками MSW.

**2.** Что не так с ключом и что сломается?
```tsx
useQuery({ queryKey: ['runs'], queryFn: () => fetchRuns(filters) });
```

**3.** Реализуй фабрику ключей для второй сущности (например, источников сигнала). Настрой инвалидацию так, чтобы создание источника сбрасывало список источников, но не прогоны.

**4.** Зависимые запросы: страница прогона грузит сам прогон, затем по его `sourceId` — источник. Второй запрос не должен стартовать раньше. Обработай случай, когда `sourceId` отсутствует.

**5.** Оптимистичное создание: новый прогон появляется в списке до ответа сервера, с временным id и признаком «сохраняется». При ошибке — исчезает с уведомлением.

**6.** Пагинация с `keepPreviousData`. Сравни поведение с ней и без неё при переключении страниц — опиши разницу в ощущениях.

**7.** Валидация ответа. Опиши схему `Run` через Zod и подключи в `queryFn`. Намеренно сломай ответ сервера (лишнее поле, неверный тип) — убедись, что ошибка ловится на границе, а не глубоко в компоненте.

**8.** Архитектурное. Перечисли всё состояние своего приложения и распредели по трём корзинам: URL, Query, клиентское. Для каждого спорного случая объясни выбор.
