// fake(ms, name) -> промис, который через ms миллисекунд резолвится значением name
// Promise.all — это другое (ждёт МАССИВ промисов). Здесь нужен обычный new Promise.
const fake = (ms, name) =>
    new Promise(resolve => setTimeout(() => resolve(name), ms));

async function f() {
    console.log(`1`);
    await null;          // даже await null уводит остаток функции в микрозадачу
    console.log(`2`);
}

// ВНИМАНИЕ: это не настоящая задержка, а блокировка потока (busy-wait).
// Event loop на эти ti миллисекунд стоит колом — таймеры и промисы не выполняются.
async function delay(ti) {
    console.log(`delay - 01`);
    const t = Date.now();
    while (Date.now() - t < ti) {}
    console.log(`delay - 02`);
}

f();                     // не ждём — "1" печатается сразу, "2" уйдёт в микрозадачу
console.log(`3`);
console.log(`A`);

await delay(500);        // top-level await работает в .mjs
console.log('прошло полсекунды');

setTimeout(() => console.log(`B`), 0);            // макрозадача (таймер)
Promise.resolve().then(() => console.log(`C`));   // микрозадача
queueMicrotask(() => console.log(`D`));           // микрозадача
console.log(`E`);                                 // синхронный код — первым

for (let i = 0; i < 3; i++) {
    const name = await fake(300 + i * 100, `fake - Name ${i}`);
    console.log(name);   // await ВОЗВРАЩАЕТ значение — его надо забрать и вывести
}

// ============================================================
// ЗАДАНИЕ: три "запроса" — последовательно vs параллельно
// ============================================================

const urls = [
    { ms: 300, name: 'a11' },
    { ms: 500, name: 'b11' },
    { ms: 200, name: 'c11' },
];

// --- Вариант 1: последовательно (await внутри цикла) ---
async function sequential() {
    const t0 = Date.now();
    const result = [];

    for (const { ms, name } of urls) {
        const value = await fake(ms, name);   // стоим и ждём каждый по очереди
        result.push(value);
    }

    console.log(`sequential: [${result}] за ${Date.now() - t0} мс`);
}

// --- Вариант 2: параллельно (Promise.all) ---
async function parallel() {
    const t0 = Date.now();

    // ВАЖНО: fake() вызывается СРАЗУ для всех трёх — три setTimeout уже тикают.
    // Promise.all только ЖДЁТ их все, а не запускает.
    const promises = urls.map(({ ms, name }) => fake(ms, name));
    const result = await Promise.all(promises);

    console.log(`parallel:   [${result}] за ${Date.now() - t0} мс`);
}

await sequential();   // ~1000 мс = 300 + 500 + 200
await parallel();     // ~500 мс  = max(300, 500, 200)

/* Ожидаемый вывод:
1
3
A
delay - 01
delay - 02
2                    <- микрозадача из f() дождалась паузы в синхронном коде
прошло полсекунды
E                    <- синхронный код обгоняет микрозадачи
C
D
B                    <- таймер после микрозадач
fake - Name 0        (через ~300 мс)
fake - Name 1        (ещё ~400 мс)
fake - Name 2        (ещё ~500 мс)
*/
