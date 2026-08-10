# Урок 30. Формы: React Hook Form + Zod

Zod закрывает главную дыру в типизации: типы стираются в рантайме, а данные приходят извне. Одна схема даёт и проверку, и тип.

---

# Часть 1. Теория

## 30.1 Проблема

TypeScript ничего не гарантирует про внешние данные (урок 05). Это компилируется и лжёт:

```ts
const run = await res.json() as Run;      // сервер мог прислать что угодно
```

Ручные предикаты (урок 07) работают, но их надо писать и синхронизировать с типами вручную. Забыл поле — тип и проверка разъехались.

**Zod разворачивает зависимость:** схема первична, тип выводится из неё. Разъехаться невозможно.

```bash
npm i zod
```

## 30.2 Схемы

```ts
import { z } from 'zod';

const RunSchema = z.object({
  id: z.string().uuid(),
  label: z.string().min(1, 'Название обязательно').max(100),
  peakHz: z.number().positive(),
  elapsedMs: z.number().int().nonnegative(),
  createdAt: z.coerce.date(),
  config: z.object({
    size: z.union([z.literal(256), z.literal(512), z.literal(1024)]),
    window: z.enum(['hann', 'hamming', 'blackman', 'rect']),
    overlap: z.number().min(0).max(0.95),
  }),
});

type Run = z.infer<typeof RunSchema>;      // тип выведен из схемы
```

**`z.infer`** — тот же приём, что `typeof` в уроке 06, но для схем. Один источник истины.

**Разбор:**
```ts
RunSchema.parse(raw);         // бросает ZodError при несоответствии
RunSchema.safeParse(raw);     // { success: true, data } | { success: false, error }
```

`safeParse` возвращает размеченное объединение — урок 08 в чужой библиотеке:
```ts
const result = RunSchema.safeParse(raw);
if (!result.success) {
  console.error(result.error.issues);
  return;
}
result.data;                  // Run, типизирован
```

**`z.coerce`** приводит типы перед проверкой — незаменимо для форм и URL, где всё строки:
```ts
z.coerce.number().int().positive()      // "1024" → 1024
z.coerce.boolean()                       // "true" → true
z.coerce.date()                          // ISO-строка → Date
```

**Уточнения:**
```ts
const ConfigSchema = z.object({
  size: z.coerce.number().int(),
  overlap: z.coerce.number(),
}).refine(
  d => (d.size & (d.size - 1)) === 0,
  { message: 'Размер должен быть степенью двойки', path: ['size'] },
).refine(
  d => d.overlap < 1,
  { message: 'Перекрытие должно быть меньше 1', path: ['overlap'] },
);
```
`path` привязывает ошибку к конкретному полю — форма покажет её под нужным инпутом.

**Композиция схем:**
```ts
const CreateRunSchema = RunSchema.omit({ id: true, createdAt: true });
const PatchRunSchema = CreateRunSchema.partial();
const WithSourceSchema = RunSchema.extend({ sourceId: z.string() });
```
Те же операции, что утилиты типов из урока 10, но на уровне значений — и тип обновляется автоматически.

## 30.3 Зачем нужен React Hook Form

Управляемая форма из урока 17 работает, но:
- каждое нажатие клавиши перерисовывает всю форму
- валидация, ошибки, «поле трогали», состояние отправки — всё вручную
- на двадцати полях это сотни строк

```bash
npm i react-hook-form @hookform/resolvers
```

**Идея RHF: поля неуправляемые, значения читаются из DOM через ref.** Ввод не вызывает рендер вообще. Перерисовывается только то, что подписано на конкретную ошибку.

## 30.4 Базовое использование

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

type FormValues = z.infer<typeof ConfigSchema>;

function ConfigForm({ onSubmit }: { onSubmit: (v: FormValues) => void }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isDirty },
    reset,
  } = useForm<FormValues>({
    resolver: zodResolver(ConfigSchema),
    defaultValues: { size: 1024, window: 'hann', overlap: 0.5 },
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <Field label="Размер FFT" error={errors.size?.message}>
        <input type="number" {...register('size')} />
      </Field>

      <Field label="Окно" error={errors.window?.message}>
        <select {...register('window')}>
          {Object.entries(WINDOWS).map(([k, i]) =>
            <option key={k} value={k}>{i.label}</option>)}
        </select>
      </Field>

      <button type="submit" disabled={isSubmitting || !isDirty}>
        {isSubmitting ? 'Сохранение…' : 'Сохранить'}
      </button>
      <button type="button" onClick={() => reset()}>Сброс</button>
    </form>
  );
}
```

**`register('size')`** возвращает `{ name, onChange, onBlur, ref }` — раскрывается в инпут спредом. Имя поля типизировано: опечатка не скомпилируется.

**`handleSubmit(onSubmit)`** делает `preventDefault`, валидирует, и вызывает коллбэк **только при успехе**. В `onSubmit` данные уже типизированы и проверены.

**`errors.size?.message`** — путь тоже типизирован, включая вложенность: `errors.config?.window?.message`.

## 30.5 Полезное из formState

```tsx
formState.isDirty          // хоть одно поле изменено
formState.dirtyFields      // какие именно
formState.isValid          // проходит валидацию (нужен mode: 'onChange')
formState.isSubmitting     // идёт отправка (для async onSubmit)
formState.isSubmitted
formState.touchedFields
```

**`formState` — прокси.** Подписка возникает только на те поля, которые ты реально читаешь. Если не обращаться к `isValid`, RHF не будет валидировать на каждое изменение. Отсюда важное: **деструктурируй только нужное**.

**Режимы валидации:**
```tsx
useForm({ mode: 'onSubmit' })     // по умолчанию — при отправке
useForm({ mode: 'onBlur' })       // при потере фокуса
useForm({ mode: 'onChange' })     // на каждое изменение — дороже
useForm({ reValidateMode: 'onChange' })   // после первой ошибки — сразу
```
Хорошая практика: `onBlur` для первой валидации, `onChange` для повторной. Пользователь не видит ошибок, пока не закончил вводить, но видит исправление сразу.

## 30.6 Контролируемые поля

Сторонние компоненты (слайдеры, селекты из UI-библиотек) не принимают `ref` — для них `Controller`:

```tsx
import { Controller } from 'react-hook-form';

<Controller
  name="window"
  control={control}
  render={({ field, fieldState }) => (
    <Select
      value={field.value}
      onChange={field.onChange}
      onBlur={field.onBlur}
      options={keysOf(WINDOWS)}
      getLabel={w => WINDOWS[w].label}
    />
  )}
/>
```

`field` содержит `{ value, onChange, onBlur, name, ref }` — интерфейс управляемого компонента из урока 17. Наш `Select` из урока 23 подходит напрямую.

Цена: контролируемое поле перерисовывается на каждое изменение. Для одного слайдера незаметно.

## 30.7 Асинхронная отправка

```tsx
const create = useCreateRun();          // мутация из урока 28

const onSubmit = async (values: FormValues) => {
  try {
    await create.mutateAsync(values);
    reset(values);                       // новые значения становятся «чистыми»
  } catch (e) {
    setError('root', {
      message: e instanceof Error ? e.message : 'Не удалось сохранить',
    });
  }
};
```

**`setError('root', ...)`** — для ошибок, не привязанных к полю. Читается как `errors.root?.message`.

**Ошибки валидации от сервера** привязываются к полям:
```tsx
if (e instanceof ApiError && e.status === 422) {
  for (const [field, message] of Object.entries(e.fieldErrors)) {
    setError(field as keyof FormValues, { message });
  }
}
```

## 30.8 Типизация

```tsx
const schema = z.object({ size: z.coerce.number() });

type Input = z.input<typeof schema>;      // { size: unknown } — до приведения
type Output = z.infer<typeof schema>;     // { size: number } — после
```

С `z.coerce` вход и выход различаются. `useForm` работает со **входными** значениями, `onSubmit` получает **выходные**:
```tsx
useForm<z.input<typeof schema>, unknown, z.output<typeof schema>>({
  resolver: zodResolver(schema),
});
```
Громоздко, но иначе типы разъезжаются. Часто проще не использовать `coerce`, а держать поля строками и приводить в схеме через `transform`.

**Пути полей типизированы:**
```tsx
register('config.window');       // ✅
register('config.windo');        // ❌ ошибка компиляции
```
Внутри — рекурсивный template literal тип по структуре объекта. Именно та задача из домашки урока 11.

---

# Часть 2. Проработка

## Задача. Схемы как граница системы

Zod применяется в трёх местах: форма, ответ сервера, параметры URL. Схема одна.

```ts
// src/features/runs/schema.ts
import { z } from 'zod';
import { FFT_SIZES, WINDOWS } from '@/types';

// union литералов из массива — приём урока 12, но для Zod
export const FftSizeSchema = z.union(
  FFT_SIZES.map(s => z.literal(s)) as unknown as
    [z.ZodLiteral<number>, z.ZodLiteral<number>, ...z.ZodLiteral<number>[]]
);

export const WindowSchema = z.enum(
  Object.keys(WINDOWS) as [string, ...string[]]
);

export const FftConfigSchema = z.object({
  size: FftSizeSchema,
  window: WindowSchema,
  overlap: z.number().min(0).max(0.95),
});

export const RunSchema = z.object({
  id: z.string().uuid(),
  label: z.string().trim().min(1, 'Укажите название').max(100),
  config: FftConfigSchema,
  peakHz: z.number().positive(),
  elapsedMs: z.number().int().nonnegative(),
  createdAt: z.coerce.date(),
});

export const CreateRunSchema = RunSchema.omit({
  id: true, createdAt: true, peakHz: true, elapsedMs: true,
});

export type Run = z.infer<typeof RunSchema>;
export type CreateRun = z.infer<typeof CreateRunSchema>;
export type FftConfig = z.infer<typeof FftConfigSchema>;
```

**Приведения в `FftSizeSchema` и `WindowSchema`** — вынужденные. `z.union` и `z.enum` требуют кортеж с минимум одним элементом, а `map` даёт обычный массив. Некрасиво, но локально; альтернатива — перечислить руками и потерять единый источник истины.

**Типы теперь выводятся из схем, а не объявляются.** Файл `types.ts` из урока 14 частично уходит: остаются константы (`WINDOWS`, `FFT_SIZES`), типы приходят из Zod.

**Применение 1. Граница с сервером** (доработка урока 28):
```ts
async function request<T>(path: string, schema: z.ZodType<T>, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, init);
  if (!res.ok) throw new ApiError(res.status, res.statusText);

  const raw: unknown = await res.json();
  const parsed = schema.safeParse(raw);

  if (!parsed.success) {
    console.error('Ответ не соответствует схеме', parsed.error.issues);
    throw new Error('Некорректный ответ сервера');
  }
  return parsed.data;
}

export const runsApi = {
  list: (signal?: AbortSignal) => request('/runs', RunSchema.array(), { signal }),
  get: (id: string) => request(`/runs/${id}`, RunSchema),
};
```

Сравни с уроком 28, где было `res.json() as Promise<T>` — заявление без проверки. Теперь ложь невозможна: если сервер изменит формат, ты узнаешь об этом сразу и в понятном месте, а не через три компонента в виде `undefined is not a function`.

**Применение 2. Форма:**
```tsx
// src/features/runs/SaveRunForm.tsx
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

type Values = z.infer<typeof CreateRunSchema>;

export function SaveRunForm({
  config, onSaved,
}: { config: FftConfig; onSaved: () => void }) {
  const create = useCreateRun();

  const {
    register, handleSubmit, control, reset, setError,
    formState: { errors, isSubmitting },
  } = useForm<Values>({
    resolver: zodResolver(CreateRunSchema),
    defaultValues: { label: '', config },
  });

  const onSubmit = async (values: Values) => {
    try {
      await create.mutateAsync(values);
      reset({ label: '', config });
      onSaved();
    } catch (e) {
      setError('root', {
        message: e instanceof ApiError && e.status === 409
          ? 'Прогон с таким названием уже есть'
          : 'Не удалось сохранить',
      });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <Field label="Название" error={errors.label?.message}>
        <input {...register('label')} autoFocus />
      </Field>

      <Field label="Размер FFT" error={errors.config?.size?.message}>
        <Controller
          name="config.size"
          control={control}
          render={({ field }) => (
            <Select
              value={field.value}
              onChange={field.onChange}
              options={FFT_SIZES}
              getLabel={s => `${s} точек`}
            />
          )}
        />
      </Field>

      {errors.root && <div className="form-error">{errors.root.message}</div>}

      <Button type="submit" loading={isSubmitting}>Сохранить</Button>
    </form>
  );
}
```

**Одна схема — три роли.** `CreateRunSchema` описывает, что можно отправить; из неё выведен тип формы, из неё же взяты правила валидации, ей же проверяется ответ. Изменение схемы автоматически меняет всё.

**`errors.config?.size?.message`** — путь во вложенном объекте, типизирован полностью.

**Применение 3. Параметры URL** (доработка урока 27):
```ts
export function useConfigFromUrl(): [FftConfig, (p: Partial<FftConfig>) => void] {
  const [params, setParams] = useSearchParams();

  const config = useMemo(() => {
    const parsed = FftConfigSchema.safeParse({
      size: Number(params.get('size')),
      window: params.get('window'),
      overlap: Number(params.get('overlap')),
    });
    return parsed.success ? parsed.data : DEFAULT_CONFIG;
  }, [params]);

  // ...patch как в уроке 27
  return [config, patch];
}
```

Двадцать строк ручной валидации из урока 27 схлопнулись в четыре. Все проверки — диапазон перекрытия, допустимость окна, корректность размера — уже описаны в схеме.

**Общий принцип, ради которого весь урок.** Валидация происходит **на границе системы** — там, где данные входят: сеть, форма, URL, файл, сообщение воркера. Внутри границы код работает с типизированными данными и не проверяет ничего. Это ровно та архитектура, которую мы наметили в уроке 07, теперь с инструментом.

---

# Часть 3. Домашка

**1.** Опиши схемой формат файла с сигналом: заголовок с частотой дискретизации и числом каналов, массив отсчётов. Провалидируй загруженный JSON, покажи понятные ошибки при несоответствии.

**2.** Почему `parse` в `queryFn` лучше, чем `as`? Сломай ответ сервера тремя способами (лишнее поле, пропущенное поле, неверный тип) и опиши, где именно проявится ошибка в каждом варианте — с Zod и без.

**3.** Форма с зависимой валидацией: перекрытие не больше 0.9 при размере до 1024 и не больше 0.75 при большем. Реализуй через `superRefine`, привяжи ошибку к полю `overlap`.

**4.** `z.input` против `z.infer`. Собери форму с `z.coerce.number()`, разберись, почему типы расходятся, и приведи два способа это решить.

**5.** Массив полей: форма с несколькими источниками сигнала, кнопки добавить/удалить. Используй `useFieldArray`. Проверь, что `key` строк не сбивает состояние (урок 16).

**6.** Ошибки сервера на поля. Сымитируй ответ 422 со списком проблемных полей, привяжи их через `setError`. Убедись, что ошибка исчезает при исправлении поля.

**7.** Замерь. Форма на 15 полей: управляемая через `useState` и на RHF. Профайлер, число рендеров на десять нажатий клавиш в одном поле. Объясни разницу.

**8.** Проверка сообщений воркера. Опиши схемы `WorkerRequest` и `WorkerResponse` из урока 26 через Zod, валидируй на обеих сторонах. Стоит ли это делать в проде — обоснуй ответ, учитывая, что оба конца пишешь ты сам.
