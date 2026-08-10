//СОВЕТ Через Search Everywhere можно найти любое действие, файл или символ в проекте. Нажми <shortcut actionId="Shift"/> <shortcut actionId="Shift"/>, набери <b>terminal</b> и нажми <shortcut actionId="EditorEnter"/>. Затем выполни в терминале <shortcut raw="npm run dev"/> и кликни по ссылке в выводе, чтобы открыть приложение в браузере.
export function setupCounter(element: HTMLElement) {
  //СОВЕТ Попробуй <shortcut actionId="GotoDeclaration"/> на <shortcut raw="counter"/>, чтобы увидеть все использования. Этим же шорткатом можно перейти к объявлению — попробуй на <shortcut raw="counter"/> в строке 13.
  let counter = 0;

  const adjustCounterValue = (value: number)  => {
    if (value >= 100) return value - 100;
    if (value <= -100) return value + 100;
    return value;
  };

  const setCounter = (value: number) => {
    counter = adjustCounterValue(value);
    //СОВЕТ В WebStorm много инспекций, которые помогают находить проблемы в проекте. А ещё есть быстрые исправления. Нажми <shortcut actionId="ShowIntentionActions"/> на <shortcut raw="text"/> и выбери <b>Inline variable</b>, чтобы убрать лишний код.
    const text = `${counter}`;
    element.innerHTML = text;
  };

  document.getElementById('increaseByOne')?.addEventListener('click', () => setCounter(counter + 1));
  document.getElementById('decreaseByOne')?.addEventListener('click', () => setCounter(counter - 1));
  document.getElementById('increaseByTwo')?.addEventListener('click', () => setCounter(counter + 2));

  //СОВЕТ В приложении в браузере кнопка <b>-2</b> не работает. Чтобы это починить, допиши код по образцу строк 19 - 21.
  document.getElementById('decreaseByTwo')

  //СОВЕТ Посмотрим, как просматривать и коммитить изменения. Нажми <shortcut actionId="GotoAction"/> и найди <b>commit</b>. Попробуй глянуть diff файла — для этого дважды кликни по main.ts.
  setCounter(0);
}

//СОВЕТ Чтобы искать текст по проекту, используй шорткат <shortcut actionId="FindInPath"/>. Нажми его и набери <b>counter</b> — все совпадения будут в одном месте.
setupCounter(document.getElementById('counter-value') as HTMLElement);

//СОВЕТ В WebStorm есть ещё много всего для продуктивной работы. Нажми <shortcut actionId="Shift"/> <shortcut actionId="Shift"/> и найди <b>Learn WebStorm</b> — откроется обучающий хаб, там есть что попробовать.
