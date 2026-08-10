console.log(`A`);
setTimeout(()=>console.log(`B`),0);
Promise.resolve().then(()=> console.log(`C`));
queueMicrotask(()=>console.log(`D`));
console.log(`E`);

function heavy(){
    const t =Date.now();
    while (Date.now() - t < 3000){}
    return 42;
}

setTimeout(()=>console.log(`Таймер сработал`),100);
console.log(heavy());
