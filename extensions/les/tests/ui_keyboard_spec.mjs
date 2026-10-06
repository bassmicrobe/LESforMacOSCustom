// SPDX-License-Identifier: MIT
// Execute the actual embedded handlers without a browser or live API requests.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const readSource = (name) => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');

function keyboardHandler(name, inputId) {
  const source = readSource(name);
  const tag = source.match(new RegExp(`<(?:textarea|input) id="${inputId}"[\\s\\S]*?>`));
  assert.ok(tag, `${name}: ${inputId} input exists`);
  const inline = tag[0].match(/onkeydown="([^"]+)"/)[1];
  const onKey = inline === 'onKey(event)'
    ? source.match(/function onKey\(e\) \{[\s\S]*?\n\}/)[0]
    : '';
  const counts = { submit: 0, prevented: 0, blurred: 0 };
  const context = vm.createContext({
    send: () => { counts.submit += 1; },
    submit: () => { counts.submit += 1; },
    ask: () => { counts.submit += 1; },
    addNote: () => { counts.submit += 1; },
    switchTrack: () => { counts.submit += 1; },
  });
  vm.runInContext(`${onKey}\nfunction handle(event) { ${inline} }`, context);
  return {
    counts,
    press: (options = {}) => context.handle.call({
      value: '変換中の日本語',
      blur: () => { counts.blurred += 1; },
    }, {
      key: 'Enter',
      metaKey: true,
      keyCode: 13,
      isComposing: false,
      preventDefault: () => { counts.prevented += 1; },
      ...options,
    }),
  };
}

const cases = [
  ['AI chat', 'ai/chat.lua', 'inp'],
  ['AI recommendations', 'ai/recommend.lua', 'inp'],
  ['project notes', 'tracking/projectnotes.lua', 'inp'],
  ['track notes', 'tracking/tracknotes.lua', 'inp'],
  ['track name', 'tracking/tracknotes.lua', 'trackInput'],
];

for (const [label, path, inputId] of cases) {
  test(`${label}: IME confirmation does not submit or switch context`, () => {
    for (const composition of [{ isComposing: true }, { keyCode: 229 }]) {
      const handler = keyboardHandler(path, inputId);
      handler.press(composition);
      assert.deepEqual(handler.counts, { submit: 0, prevented: 0, blurred: 0 });
    }
  });

  test(`${label}: the normal shortcut still submits once`, () => {
    const handler = keyboardHandler(path, inputId);
    handler.press();
    assert.equal(handler.counts.submit, 1);
  });

  if (inputId === 'inp') {
    test(`${label}: plain Enter remains available for a newline`, () => {
      const handler = keyboardHandler(path, inputId);
      handler.press({ metaKey: false });
      assert.deepEqual(handler.counts, { submit: 0, prevented: 0, blurred: 0 });
    });
  }
}

for (const [label, path] of [['project notes', 'tracking/projectnotes.lua'], ['track notes', 'tracking/tracknotes.lua']]) {
  function contextGuard({ draft = '', pending = false, accepted = false } = {}) {
    const source = readSource(path);
    const declaration = source.match(/function confirmContextChange\(\) \{[\s\S]*?\n\}/);
    assert.ok(declaration, `${label} has a context-change guard`);
    let prompts = 0;
    const context = vm.createContext({
      notePending: pending,
      deletionPending: false,
      document: { getElementById: (id) => id === 'inp' ? { value: draft } : { disabled: false } },
      setStatus: () => {},
      confirm: () => { prompts += 1; return accepted; },
    });
    vm.runInContext(declaration[0], context);
    return { result: context.confirmContextChange(), prompts };
  }

  test(`${label}: pending saves block context changes without discarding input`, () => {
    assert.deepEqual(contextGuard({ draft: '未保存のメモ', pending: true, accepted: true }), { result: false, prompts: 0 });
  });

  test(`${label}: draft disposal requires confirmation`, () => {
    assert.deepEqual(contextGuard({ draft: '未保存のメモ', accepted: false }), { result: false, prompts: 1 });
    assert.deepEqual(contextGuard({ draft: '未保存のメモ', accepted: true }), { result: true, prompts: 1 });
  });

  test(`${label}: an empty draft changes context without a prompt`, () => {
    assert.deepEqual(contextGuard(), { result: true, prompts: 0 });
  });
}
