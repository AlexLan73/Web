# Урок 32. Тесты: Vitest + Testing Library

Последний урок блока экосистемы. Что тестировать, что не тестировать, и почему тест на реализацию хуже отсутствия теста.

---

# Часть 1. Теория

## 32.1 Настройка

```bash
npm i -D vitest @testing-library/react @testing-library/user-event @testing-library/jest-dom jsdom
```

```ts
// vite.config.ts
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.ts',
  },
});
```

```ts
// src/test/setup.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(cleanup);
```

Vitest использует ту же конфигурацию, что и сборка: те же алиасы, тот же TypeScript, тот же transform. Настраивать отдельно почти нечего — главное преимущество перед Jest.

`jsdom` — эмуляция DOM в Node. Не браузер: нет реальной раскладки, `getBoundingClientRect` возвращает нули, canvas не рисует. Это ограничивает, что можно тестировать (см. 32.6).

## 32.2 Что тестировать

По убыванию отдачи:

**1. Чистые функции.** DSP-расчёты, форматирование, редьюсеры, схемы Zod. Дёшево писать, быстро выполняются, ловят настоящие ошибки.

**2. Редьюсеры и хуки с логикой.** Таблица переходов автомата из урока 25 покрывается за десять строк.

**3. Компоненты с поведением.** Формы, взаимодействия, условный рендер.

**4. Интеграционные сценарии.** Открыл, заполнил, отправил, увидел результат.

**Что не тестировать:** разметку без логики, стили, сторонние библиотеки, тривиальные геттеры. Тест, который сломается от переименования CSS-класса, — не тест, а якорь.

## 32.3 Главный принцип Testing Library

> Тестируй так, как пользуется пользователь.

Пользователь не знает про пропсы, состояние и имена компонентов. Он видит текст, метки, роли и кликает по ним.

**Приоритет селекторов:**
```tsx
getByRole('button', { name: 'Сохранить' })    // ✅ лучший
getByLabelText('Размер FFT')                   // ✅ для полей формы
getByPlaceholderText('Поиск')
getByText('Нет данных')
getByTestId('spectrum-canvas')                 // ⚠️ последнее средство
```

`getByRole` первый не случайно: он проверяет и доступность заодно. Если элемент не находится по роли — вероятно, у него нет метки, и скринридер его тоже не найдёт.

**Три семейства:**
- `getBy*` — бросает, если не нашёл. Для того, что должно быть
- `queryBy*` — возвращает `null`. Для проверки отсутствия
- `findBy*` — возвращает промис, ждёт появления. Для асинхронного

```tsx
expect(screen.queryByText('Ошибка')).not.toBeInTheDocument();
expect(await screen.findByText('Готово')).toBeInTheDocument();
```

## 32.4 `userEvent` вместо `fireEvent`

```tsx
import userEvent from '@testing-library/user-event';

const user = userEvent.setup();
await user.click(screen.getByRole('button', { name: 'Запустить' }));
await user.type(screen.getByLabelText('Название'), 'Тест 1');
await user.selectOptions(screen.getByLabelText('Окно'), 'blackman');
await user.keyboard('{Escape}');
```

`fireEvent.click` диспатчит одно событие. `userEvent.click` воспроизводит всю последовательность: `pointerdown`, `mousedown`, `focus`, `pointerup`, `mouseup`, `click`. Ближе к реальности — ловит больше багов.

Все методы асинхронные, `await` обязателен.

## 32.5 Тестирование компонентов

```tsx
import { render, screen } from '@testing-library/react';
import { describe, test, expect, vi } from 'vitest';

describe('ConfigEditor', () => {
  test('вызывает onChange при смене размера', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();

    render(
      <ConfigEditor
        value={{ size: 1024, window: 'hann', overlap: 0.5 }}
        onChange={onChange}
      />
    );

    await user.selectOptions(screen.getByLabelText('Размер FFT'), '2048');

    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ size: 2048 })
    );
  });

  test('блокирует поля при disabled', () => {
    render(<ConfigEditor value={config} onChange={vi.fn()} disabled />);
    expect(screen.getByLabelText('Размер FFT')).toBeDisabled();
  });
});
```

**Обёртка с провайдерами** — большинство компонентов требует роутер, Query, тему:
```tsx
// src/test/render.tsx
function AllProviders({ children }: { children: React.ReactNode }) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  );
}

export function renderWithProviders(ui: React.ReactElement) {
  return {
    user: userEvent.setup(),
    ...render(ui, { wrapper: AllProviders }),
  };
}
```

**`retry: false` в тестах обязателен** — иначе неудачный запрос будет повторяться, и тест зависнет на таймауте. **Новый `QueryClient` на каждый тест** — иначе кеш протечёт между тестами.

## 32.6 Что плохо тестируется в jsdom

**Canvas.** Контекст есть, но ничего не рисует. Проверить можно только, что `getContext` вызван и метод отрисовки получил правильные аргументы — через мок:
```tsx
const ctx = { clearRect: vi.fn(), beginPath: vi.fn(), lineTo: vi.fn(), stroke: vi.fn() };
vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(ctx as never);
```
Это тест на реализацию, ценность низкая. Лучше вынести расчёт координат в чистую функцию и тестировать её.

**Размеры и позиции.** `getBoundingClientRect` возвращает нули. Всё, что зависит от раскладки, в jsdom не проверяется.

**`ResizeObserver`, `IntersectionObserver`** — отсутствуют, нужны моки.

**Web Worker** — нет. Мокай модуль целиком:
```ts
vi.mock('@/lib/dsp', () => ({
  computeSpectrum: vi.fn().mockResolvedValue(new Float32Array(512)),
}));
```

Для настоящей проверки визуального поведения — Playwright с реальным браузером. Это отдельный инструмент и отдельный слой тестов.

## 32.7 Моки сети

**MSW** перехватывает запросы на уровне сети — код приложения не знает, что он в тесте:

```bash
npm i -D msw
```

```ts
// src/test/server.ts
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';

export const server = setupServer(
  http.get('/api/runs', () => HttpResponse.json([
    { id: '1', label: 'Тест', peakHz: 440, elapsedMs: 12, config: {...},
      createdAt: '2026-01-01T00:00:00Z' },
  ])),
);
```

```ts
// setup.ts
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

`onUnhandledRequest: 'error'` — забытый мок падает явно, а не тихо уходит в сеть.

Переопределение в конкретном тесте:
```ts
server.use(http.get('/api/runs', () => new HttpResponse(null, { status: 500 })));
```

Преимущество перед моком `fetch`: тестируется реальный код запроса, включая заголовки, сериализацию и обработку статусов.

## 32.8 Что делает тест плохим

**Тест на реализацию:**
```tsx
expect(component.state.isOpen).toBe(true);          // ❌ внутренности
expect(screen.getByRole('dialog')).toBeVisible();   // ✅ поведение
```
Первый сломается при рефакторинге, который ничего не сломал для пользователя. Такие тесты не защищают, а мешают менять код.

**Тест, повторяющий реализацию:**
```tsx
expect(formatHz(1000)).toBe(`${1000 / 1000} кГц`);   // ❌ та же формула
expect(formatHz(1000)).toBe('1 кГц');                 // ✅ ожидаемый результат
```

**Хрупкие селекторы:** по классу, по индексу в списке, по структуре DOM.

**`waitFor` вместо `findBy`:**
```tsx
await waitFor(() => expect(screen.getByText('Готово')).toBeInTheDocument());  // многословно
expect(await screen.findByText('Готово')).toBeInTheDocument();                 // ✅
```

**Отсутствие `await`** перед `userEvent` — самая частая причина «тест иногда падает».

---

# Часть 2. Проработка

## Задача. Три слоя тестов

**Слой 1. Чистые функции — самые дешёвые и полезные.**

```ts
// src/lib/dsp.test.ts
import { describe, test, expect } from 'vitest';
import { hzToBin, binToHz, formatFreq, applyWindow } from './dsp';

describe('преобразование частот', () => {
  test('bin и hz обратимы', () => {
    const sampleRate = 44100, size = 1024;
    for (const bin of [0, 1, 100, 511]) {
      const hz = binToHz(bin, sampleRate, size);
      expect(hzToBin(hz, sampleRate, size)).toBe(bin);
    }
  });

  test('нулевой бин — постоянная составляющая', () => {
    expect(binToHz(0, 44100, 1024)).toBe(0);
  });

  test('последний бин близок к Найквисту', () => {
    expect(binToHz(512, 44100, 1024)).toBeCloseTo(22050, 1);
  });
});

describe('formatFreq', () => {
  test.each([
    [440, 'hz', '440.0 Гц'],
    [1000, 'khz', '1.000 кГц'],
    [22050, 'khz', '22.050 кГц'],
    [0, 'hz', '0.0 Гц'],
  ] as const)('formatFreq(%i, %s) === %s', (hz, unit, expected) => {
    expect(formatFreq(hz, unit)).toBe(expected);
  });
});

describe('оконные функции', () => {
  test('прямоугольное окно не меняет сигнал', () => {
    const input = new Float32Array([1, 2, 3, 4]);
    expect(Array.from(applyWindow(input, 'rect'))).toEqual([1, 2, 3, 4]);
  });

  test('окно Ханна обнуляет края', () => {
    const out = applyWindow(new Float32Array(8).fill(1), 'hann');
    expect(out[0]).toBeCloseTo(0, 5);
    expect(out[7]).toBeCloseTo(0, 5);
    expect(out[4]).toBeGreaterThan(0.9);
  });

  test('сохраняет длину', () => {
    expect(applyWindow(new Float32Array(1024), 'blackman')).toHaveLength(1024);
  });
});
```

**`test.each`** — таблица случаев одной строкой на случай. Для форматирования и математики идеально.

**Свойства вместо конкретных значений.** «Обратимость», «сохраняет длину», «края обнуляются» — проверяют суть, а не переписывают формулу. Такой тест переживёт смену реализации.

**Слой 2. Редьюсер — вся таблица переходов.**

```ts
// src/features/analysis/state/panel.test.ts
import { describe, test, expect } from 'vitest';
import { panelReducer, initialState, type PanelState } from './panel';

const running: PanelState = {
  ...initialState,
  analysis: { status: 'running', progress: 0.3 },
};

describe('panelReducer', () => {
  test('start переводит в running', () => {
    const next = panelReducer(initialState, { type: 'run/start' });
    expect(next.analysis).toEqual({ status: 'running', progress: 0 });
  });

  test('повторный start игнорируется', () => {
    expect(panelReducer(running, { type: 'run/start' })).toBe(running);
  });

  test('progress вне running игнорируется', () => {
    const action = { type: 'run/progress', value: 0.5 } as const;
    expect(panelReducer(initialState, action)).toBe(initialState);
  });

  test('progress в running обновляется', () => {
    const next = panelReducer(running, { type: 'run/progress', value: 0.7 });
    expect(next.analysis).toMatchObject({ status: 'running', progress: 0.7 });
  });

  test('finish вне running игнорируется', () => {
    const action = { type: 'run/finish', bins: new Float32Array(4), elapsedMs: 10 } as const;
    expect(panelReducer(initialState, action)).toBe(initialState);
  });

  test('cancel возвращает в idle из любого состояния', () => {
    for (const state of [initialState, running]) {
      expect(panelReducer(state, { type: 'run/cancel' }).analysis)
        .toEqual({ status: 'idle' });
    }
  });

  test('параметры не меняются во время расчёта', () => {
    const next = panelReducer(running, { type: 'config/patch', patch: { size: 2048 } });
    expect(next).toBe(running);
  });

  test('undo на пустой истории не ломается', () => {
    expect(panelReducer(initialState, { type: 'config/undo' })).toBe(initialState);
  });
});
```

**`toBe` для проверки «ничего не изменилось».** Редьюсер возвращает **тот же объект**, а не копию, — сравнение по ссылке проверяет это точно. Заодно подтверждает, что React не будет перерисовывать.

**Ни React, ни рендера, ни моков.** Восемь тестов покрывают всю логику автомата и выполняются за миллисекунды. Это та отдача, ради которой стоило выносить логику в редьюсер (урок 25).

**Слой 3. Компонент со сценарием.**

```tsx
// src/features/runs/SaveRunForm.test.tsx
import { describe, test, expect, vi } from 'vitest';
import { screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { renderWithProviders } from '@/test/render';
import { server } from '@/test/server';
import { SaveRunForm } from './SaveRunForm';

const config = { size: 1024, window: 'hann', overlap: 0.5 } as const;

describe('SaveRunForm', () => {
  test('не отправляет с пустым названием', async () => {
    const onSaved = vi.fn();
    const { user } = renderWithProviders(
      <SaveRunForm config={config} onSaved={onSaved} />
    );

    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    expect(await screen.findByText('Укажите название')).toBeInTheDocument();
    expect(onSaved).not.toHaveBeenCalled();
  });

  test('сохраняет и сообщает наверх', async () => {
    const onSaved = vi.fn();
    const { user } = renderWithProviders(
      <SaveRunForm config={config} onSaved={onSaved} />
    );

    await user.type(screen.getByLabelText('Название'), 'Прогон 1');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    await vi.waitFor(() => expect(onSaved).toHaveBeenCalledOnce());
  });

  test('показывает ошибку сервера', async () => {
    server.use(
      http.post('/api/runs', () => new HttpResponse(null, { status: 500 }))
    );

    const { user } = renderWithProviders(
      <SaveRunForm config={config} onSaved={vi.fn()} />
    );

    await user.type(screen.getByLabelText('Название'), 'Прогон 1');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    expect(await screen.findByText(/не удалось сохранить/i)).toBeInTheDocument();
  });
});
```

**Разбор.**

**Ни одного обращения к внутренностям.** Тест не знает про RHF, Zod, Query, `useState`. Он вводит текст, нажимает кнопку, смотрит на результат — ровно то, что делает пользователь. Замени RHF на что угодно — тест продолжит работать.

**Сообщение об ошибке взято из схемы Zod** (урок 30). Тест проверяет, что валидация подключена и её результат виден — не то, как она устроена.

**Регулярка в `findByText`** — устойчивее точного совпадения к изменениям формулировки и регистра.

**Мок сервера переопределяется точечно** внутри теста, `resetHandlers` в `afterEach` возвращает исходное состояние.

**Тест на хук:**
```ts
// src/hooks/useDebounced.test.ts
import { renderHook, act } from '@testing-library/react';
import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';

describe('useDebounced', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  test('возвращает значение с задержкой', () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounced(value, 300),
      { initialProps: { value: 'a' } },
    );

    expect(result.current).toBe('a');

    rerender({ value: 'b' });
    expect(result.current).toBe('a');            // ещё старое

    act(() => { vi.advanceTimersByTime(300); });
    expect(result.current).toBe('b');
  });

  test('сбрасывает таймер при быстрых изменениях', () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounced(value, 300),
      { initialProps: { value: 'a' } },
    );

    rerender({ value: 'b' });
    act(() => { vi.advanceTimersByTime(200); });
    rerender({ value: 'c' });
    act(() => { vi.advanceTimersByTime(200); });

    expect(result.current).toBe('a');             // 400 мс прошло, но таймер сбрасывался

    act(() => { vi.advanceTimersByTime(100); });
    expect(result.current).toBe('c');
  });
});
```

**Фейковые таймеры** обязательны — иначе тест ждал бы реальные 300 мс, а для дебаунса в секунду это уже неприемлемо.

**`act` вокруг продвижения времени** — внутри произойдёт `setState`, React должен успеть применить рендер.

---

# Часть 3. Домашка

**1.** Настрой Vitest, напиши первые тесты на функции из `lib/dsp.ts`. Добейся, чтобы `npm test` проходил.

**2.** Покрой редьюсер из урока 25 полностью — все действия во всех состояниях. Затем добавь новое действие и убедись, что тесты подсказали, где ещё нужна обработка.

**3.** Протестируй схемы Zod: валидные данные проходят, каждое нарушение даёт ошибку с ожидаемым `path`. Используй `safeParse` и проверяй `error.issues`.

**4.** Настрой MSW. Протестируй `RunsPage`: загрузка, успешный список, пустой список, ошибка сервера, повторная попытка.

**5.** Почему этот тест ненадёжен и как переписать?
```tsx
test('открывает панель', () => {
  render(<Panel title="X" />);
  fireEvent.click(document.querySelector('.panel-toggle')!);
  expect(document.querySelector('.panel-body')).toBeTruthy();
});
```

**6.** Тест на `useSelection` из урока 29: одиночный клик, повторный клик снимает, shift-выделение диапазона, `clear`. Учти, что стор глобальный — сбрасывай между тестами.

**7.** Вынеси расчёт координат отрисовки спектра из `SpectrumCanvas` в чистую функцию `binsToPath(bins, width, height, range)`. Покрой тестами. Объясни, почему это лучше, чем мокать canvas.

**8.** Интеграционный сценарий целиком: открыть страницу анализа, изменить размер FFT, запустить расчёт, дождаться результата, сохранить прогон, увидеть его в списке. Воркер и API мокай. Оцени, сколько времени занял этот тест и стоит ли он того по сравнению с четырьмя отдельными.
