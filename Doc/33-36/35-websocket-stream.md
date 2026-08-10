# Урок 35. WebSocket-поток в React

Соединение живёт дольше компонента, данные идут быстрее, чем нужно рендерить, сеть рвётся. Три задачи, три решения.

---

# Часть 1. Теория

## 35.1 Где живёт соединение

Первое решение — самое важное.

**В компоненте через `useEffect`** (как в уроке 19) годится, пока соединение нужно одному поддереву и его разрыв при уходе со страницы допустим.

**В сторе** — когда соединение должно переживать навигацию, а состояние нужно в разных местах: индикатор в шапке, панель статуса, график.

Для приборной панели — второе. Пользователь переключился на список прогонов и вернулся — соединение не должно рваться и переподключаться.

```ts
// src/store/connection.ts
type ConnectionState =
  | { status: 'disconnected' }
  | { status: 'connecting'; attempt: number }
  | { status: 'connected'; since: number; sampleRate: number }
  | { status: 'reconnecting'; attempt: number; nextRetryAt: number }
  | { status: 'failed'; reason: string };
```

Размеченное объединение — пятый раз за курс, и снова оно же. Состояния соединения устроены ровно как автомат протокола.

**Сам сокет — не в состоянии стора.** Это императивный объект, менять его не через `set`. Держи в модульной переменной рядом со стором или в замыкании:

```ts
let socket: WebSocket | null = null;
let retryTimer: number | null = null;
```

В состоянии — только то, что отображается.

## 35.2 Переподключение

Сеть рвётся всегда. Правильное переподключение — экспоненциальная задержка с джиттером:

```ts
function backoffMs(attempt: number): number {
  const base = Math.min(30_000, 500 * 2 ** attempt);   // 0.5, 1, 2, 4... до 30 сек
  return base * (0.5 + Math.random() * 0.5);            // джиттер ±50%
}
```

**Зачем джиттер.** Без него все клиенты, отвалившиеся при перезапуске сервера, ломятся обратно одновременно и роняют его снова. Случайный разброс размазывает нагрузку.

**Когда не переподключаться:**
- пользователь отключился сам — намеренное действие
- код закрытия 1000 (нормальное закрытие) или 1008 (нарушение политики)
- исчерпан лимит попыток

```ts
socket.onclose = (e) => {
  if (intentional || e.code === 1000 || attempt >= MAX_ATTEMPTS) {
    setState({ status: 'disconnected' });
    return;
  }
  scheduleReconnect(attempt + 1);
};
```

**`navigator.onLine`** позволяет не тратить попытки, когда сети нет вообще:
```ts
window.addEventListener('online', () => { if (shouldReconnect) connectNow(); });
```

## 35.3 Приём бинарных данных

```ts
socket.binaryType = 'arraybuffer';     // по умолчанию 'blob' — медленнее
```

С `blob` каждое сообщение требует асинхронного `await blob.arrayBuffer()`. С `arraybuffer` данные приходят сразу — на 60 пакетах в секунду разница заметна.

```ts
socket.onmessage = (e: MessageEvent<ArrayBuffer>) => {
  const packet = parsePacket(e.data);      // из урока 33
  if (!packet) { stats.malformed++; return; }

  switch (packet.type) {
    case 'samples': {
      if (packet.sequence !== expectedSeq) stats.lost += packet.sequence - expectedSeq;
      expectedSeq = packet.sequence + 1;
      latestRef.current = packet.data;      // ← просто перезапись, без setState
      stats.received++;
      break;
    }
    case 'meta':
      useConnection.setState({
        status: 'connected', since: Date.now(), sampleRate: packet.sampleRate,
      });
      break;
    case 'error':
      console.warn('Сервер сообщил об ошибке:', packet.message);
      break;
  }
};
```

**Ключевая строка — `latestRef.current = packet.data`.** Ни `setState`, ни `dispatch`, ни обновления стора. React о пакетах не знает. Это контур 3 из урока 33.

## 35.4 Развязка частот

Данные приходят с частотой источника (может быть и 200 Гц), рисовать нужно с частотой экрана (60 Гц), статистику показывать раз в секунду. Три разные частоты — три механизма:

| Что | Частота | Механизм |
|---|---|---|
| Приём пакетов | сколько шлёт сервер | `onmessage` → запись в ref |
| Отрисовка | 60 Гц | `requestAnimationFrame` |
| Метрики | 1 Гц | `setInterval` → `setState` |

```ts
// метрики — единственное, что попадает в React
useEffect(() => {
  const id = setInterval(() => {
    setStats({
      rate: statsRef.current.received,
      lost: statsRef.current.lost,
      malformed: statsRef.current.malformed,
    });
    statsRef.current.received = 0;
  }, 1000);
  return () => clearInterval(id);
}, []);
```

Один рендер в секунду вместо двухсот. При этом пользователь видит и живой график, и актуальные цифры.

**Пропуск устаревших кадров бесплатен.** Если пришло 200 пакетов, а кадров было 60 — `latestRef.current` перезаписывался, рисуется последний. Для спектра в реальном времени это правильное поведение: старые кадры не нужны.

Если нужны все данные (запись, накопление, усреднение) — кольцевой буфер, см. проработку.

## 35.5 Обратное давление

Если обработка медленнее приёма, очередь растёт и память кончается. Варианты:

**Отбрасывать** — для отображения в реальном времени правильно. Одна переменная, перезапись.

**Кольцевой буфер фиксированного размера** — когда нужна короткая история:
```ts
class RingBuffer {
  private data: Float32Array;
  private head = 0;
  private filled = 0;

  constructor(private capacity: number) {
    this.data = new Float32Array(capacity);
  }

  push(chunk: Float32Array): void {
    for (let i = 0; i < chunk.length; i++) {
      this.data[this.head] = chunk[i]!;
      this.head = (this.head + 1) % this.capacity;
    }
    this.filled = Math.min(this.capacity, this.filled + chunk.length);
  }

  read(out: Float32Array): number {
    const n = Math.min(out.length, this.filled);
    const start = (this.head - n + this.capacity) % this.capacity;
    for (let i = 0; i < n; i++) out[i] = this.data[(start + i) % this.capacity]!;
    return n;
  }
}
```

Фиксированная память, старое вытесняется автоматически. Знакомая конструкция — та же, что в DMA-буферах.

**Сообщить серверу замедлиться** — если протокол позволяет. `socket.bufferedAmount` показывает, сколько байт ждёт отправки; растущее значение означает, что клиент не успевает.

## 35.6 Тонкости

**Сообщения до открытия теряются.** `socket.send()` при `readyState !== OPEN` бросает. Либо очередь, либо проверка:
```ts
if (socket?.readyState === WebSocket.OPEN) socket.send(data);
```

**Heartbeat.** Прокси и балансировщики рвут «тихие» соединения через 30-60 секунд. Ping раз в 20 секунд решает. Браузерный API не даёт доступа к протокольным ping/pong — шли своё сообщение.

**Вкладка в фоне.** `requestAnimationFrame` останавливается, `setInterval` дросселируется до 1 Гц, но `onmessage` продолжает работать. Данные копятся, отрисовка стоит — с перезаписью одной переменной это безопасно, с буфером надо следить.

**StrictMode.** Двойной вызов эффекта означает два подключения, если очистка неправильная. Именно тот случай, ради которого StrictMode существует (урок 19).

**Закрытие при уходе со страницы:**
```ts
window.addEventListener('beforeunload', () => socket?.close(1000, 'unload'));
```
Без этого сервер узнает о разрыве только по таймауту.

---

# Часть 2. Проработка

## Задача. Клиент потока целиком

**Слой 1: транспорт — чистый TypeScript, ноль React.**

```ts
// src/lib/stream/client.ts
import { parsePacket, type Packet } from './protocol';

export type StreamEvent =
  | { type: 'connecting'; attempt: number }
  | { type: 'open'; sampleRate: number }
  | { type: 'packet'; data: Float32Array; sequence: number }
  | { type: 'closed'; code: number; willRetry: boolean }
  | { type: 'failed'; reason: string };

type Options = {
  url: string;
  maxAttempts?: number;
  onEvent: (e: StreamEvent) => void;
};

export class StreamClient {
  private socket: WebSocket | null = null;
  private retryTimer: number | null = null;
  private heartbeat: number | null = null;
  private attempt = 0;
  private intentional = false;
  private expectedSeq = 0;

  constructor(private opts: Options) {}

  connect(): void {
    this.intentional = false;
    this.open();
  }

  disconnect(): void {
    this.intentional = true;
    this.clearTimers();
    this.socket?.close(1000, 'client disconnect');
    this.socket = null;
  }

  private open(): void {
    this.opts.onEvent({ type: 'connecting', attempt: this.attempt });

    const socket = new WebSocket(this.opts.url);
    socket.binaryType = 'arraybuffer';
    this.socket = socket;

    socket.onopen = () => {
      this.attempt = 0;
      this.expectedSeq = 0;
      this.heartbeat = window.setInterval(() => {
        if (socket.readyState === WebSocket.OPEN) socket.send('ping');
      }, 20_000);
    };

    socket.onmessage = (e: MessageEvent<ArrayBuffer | string>) => {
      if (typeof e.data === 'string') return;          // pong
      const packet = parsePacket(e.data);
      if (!packet) return;
      this.handlePacket(packet);
    };

    socket.onclose = (e) => {
      this.clearTimers();
      this.socket = null;

      const max = this.opts.maxAttempts ?? 8;
      const willRetry = !this.intentional && e.code !== 1000 && this.attempt < max;

      this.opts.onEvent({ type: 'closed', code: e.code, willRetry });

      if (willRetry) {
        this.attempt++;
        this.retryTimer = window.setTimeout(() => this.open(), backoffMs(this.attempt));
      } else if (!this.intentional) {
        this.opts.onEvent({ type: 'failed', reason: `Соединение потеряно (код ${e.code})` });
      }
    };

    socket.onerror = () => { /* onclose придёт следом */ };
  }

  private handlePacket(p: Packet): void {
    switch (p.type) {
      case 'meta':
        this.opts.onEvent({ type: 'open', sampleRate: p.sampleRate });
        break;
      case 'samples':
        this.opts.onEvent({ type: 'packet', data: p.data, sequence: p.sequence });
        break;
      case 'error':
        this.opts.onEvent({ type: 'failed', reason: p.message });
        break;
    }
  }

  private clearTimers(): void {
    if (this.retryTimer !== null) clearTimeout(this.retryTimer);
    if (this.heartbeat !== null) clearInterval(this.heartbeat);
    this.retryTimer = this.heartbeat = null;
  }
}

const backoffMs = (attempt: number): number => {
  const base = Math.min(30_000, 500 * 2 ** attempt);
  return base * (0.5 + Math.random() * 0.5);
};
```

**Класс, а не хук.** Соединение — императивный объект с жизненным циклом, класс выражает это естественно. И главное: тестируется без React, с мок-сокетом.

**`StreamEvent` — размеченное объединение** на границе транспорта и приложения. Потребитель обязан разобрать все случаи.

**Слой 2: связь со стором и данными.**

```ts
// src/features/source/useStream.ts
import { useEffect, useRef, useState } from 'react';
import { StreamClient } from '@/lib/stream/client';
import { useConnection } from '@/store/connection';

type Stats = { rate: number; lost: number; total: number };

export function useStream(url: string | null) {
  const latestRef = useRef<Float32Array | null>(null);
  const countersRef = useRef({ received: 0, lost: 0, total: 0, expectedSeq: 0 });
  const [stats, setStats] = useState<Stats>({ rate: 0, lost: 0, total: 0 });

  // --- соединение ---
  useEffect(() => {
    if (!url) {
      useConnection.setState({ status: 'disconnected' });
      return;
    }

    const client = new StreamClient({
      url,
      onEvent: (e) => {
        switch (e.type) {
          case 'connecting':
            useConnection.setState(
              e.attempt === 0
                ? { status: 'connecting', attempt: 0 }
                : { status: 'reconnecting', attempt: e.attempt, nextRetryAt: Date.now() }
            );
            break;

          case 'open':
            useConnection.setState({
              status: 'connected', since: Date.now(), sampleRate: e.sampleRate,
            });
            break;

          case 'packet': {
            const c = countersRef.current;
            if (e.sequence > c.expectedSeq) c.lost += e.sequence - c.expectedSeq;
            c.expectedSeq = e.sequence + 1;
            c.received++;
            c.total++;
            latestRef.current = e.data;        // ← горячий путь, без React
            break;
          }

          case 'failed':
            useConnection.setState({ status: 'failed', reason: e.reason });
            break;
        }
      },
    });

    client.connect();
    return () => client.disconnect();
  }, [url]);

  // --- метрики раз в секунду ---
  useEffect(() => {
    const id = setInterval(() => {
      const c = countersRef.current;
      setStats({ rate: c.received, lost: c.lost, total: c.total });
      c.received = 0;
    }, 1000);
    return () => clearInterval(id);
  }, []);

  return { latestRef, stats };
}
```

**Разбор.**

**`case 'packet'` не трогает React вообще.** Ни `setState`, ни `setStates` стора — только запись в refs. Это горячий путь, он выполняется 60-200 раз в секунду.

**Состояние соединения — в стор через `setState`.** Оно меняется редко (подключились, отвалились), доступно из шапки и панели статуса без проброса. `useConnection.setState` вызывается вне React-контекста — законно, Zustand это позволяет (урок 29).

**Очистка возвращает `client.disconnect()`.** В StrictMode эффект выполнится дважды: подключение → отключение → подключение. Второе подключение корректно, потому что `disconnect` ставит `intentional = true` и гасит таймеры — переподключения не будет.

**Метрики отдельным эффектом** с пустыми зависимостями. Один рендер в секунду.

**Использование:**
```tsx
export function AnalysisPage() {
  const [config] = useConfigFromUrl();
  const [url, setUrl] = useState<string | null>(null);
  const { latestRef, stats } = useStream(url);

  const connection = useConnection(s => s.status);
  const sampleRate = useConnection(s => s.status === 'connected' ? s.sampleRate : 44100);

  const spectrumRef = useSpectrum(latestRef, config);     // расчёт в воркере
  const getBins = useCallback(() => spectrumRef.current, [spectrumRef]);

  return (
    <>
      <Panel title="Источник" actions={<ConnectionBadge />}>
        <StreamConnect url={url} onConnect={setUrl} onDisconnect={() => setUrl(null)} />
        {connection === 'connected' && (
          <dl className="text-xs font-mono">
            <dt>Пакетов/с</dt><dd>{stats.rate}</dd>
            <dt>Потеряно</dt><dd>{stats.lost}</dd>
          </dl>
        )}
      </Panel>

      <Panel title="Спектр">
        <SpectrumCanvas getBins={getBins} sampleRate={sampleRate} zoom={1} />
      </Panel>
    </>
  );
}
```

**Проверь конвейер целиком.** Профайлер React при работающем потоке: `AnalysisPage` перерисовывается раз в секунду (метрики), `SpectrumCanvas` — ноль раз, картинка обновляется 60 раз в секунду. Отключи сеть в DevTools: статус переходит в `reconnecting`, задержки растут экспоненциально, включи обратно — соединение восстанавливается само.

---

# Часть 3. Домашка

**1.** Реализуй `StreamClient` полностью, покрой тестами с мок-сокетом. Проверь: переподключение с растущей задержкой, отсутствие переподключения при коде 1000, остановка после лимита попыток, отсутствие переподключения после `disconnect()`.

**2.** Напиши тестовый сервер на Node (`ws`), шлющий синтетический сигнал в формате из урока 33. Параметры: частота пакетов, размер, форма сигнала. Пригодится для всех остальных задач.

**3.** Кольцевой буфер из 35.5: реализуй, покрой тестами (переполнение, чтение больше накопленного, чтение через границу). Подключи к потоку так, чтобы FFT считалась по перекрывающимся окнам из накопленных данных.

**4.** Обнаружение потерь. Настрой сервер терять каждый двадцатый пакет, убедись, что счётчик считает верно. Добавь индикатор качества связи с порогами.

**5.** Вкладка в фоне. Проверь, что происходит с потоком при переключении на другую вкладку на минуту. Опиши поведение с перезаписью переменной и с кольцевым буфером. Нужна ли специальная обработка?

**6.** Heartbeat. Отключи ping, поставь прокси с таймаутом 30 секунд (или сымитируй), убедись, что соединение рвётся. Включи — проверь, что живёт.

**7.** Обратное давление. Разгони сервер до 500 пакетов в секунду по 8192 отсчёта. Найди, что становится узким местом: приём, парсинг, FFT или отрисовка. Профилируй, не угадывай.

**8.** Архитектурное. Сейчас соединение живёт в эффекте хука, а состояние в сторе. Перенеси весь `StreamClient` в стор, чтобы он переживал размонтирование страницы. Опиши, что усложнилось и что упростилось, и какой вариант выбрал бы для продакшена.
