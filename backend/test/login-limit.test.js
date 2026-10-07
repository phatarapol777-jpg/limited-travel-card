const test = require('node:test');
const assert = require('node:assert');
const { startServer } = require('./helpers');

let s;
test.before(async () => {
  s = await startServer({ LOGIN_RATE_MAX: '3', LOGIN_RATE_WINDOW_MS: '2500' });
});
test.after(() => s.stop());

const login = (username, password) => s.call('POST', '/auth/login', { username, password });

test('repeated wrong passwords for one username are slowed down, other usernames are not', async () => {
  const victim = await s.register('victim');
  for (let i = 0; i < 3; i++) assert.equal((await login(victim.username, 'wrong-password')).status, 401);
  const blocked = await login(victim.username, 'wrong-password');
  assert.equal(blocked.status, 429);
  // even the right password waits: otherwise guesses would still be answered
  assert.equal((await login(victim.username, 'secret123')).status, 429);
  // another account is unaffected
  const other = await s.register('bystander');
  assert.equal((await login(other.username, 'secret123')).status, 200);
});

test('the wait ends by itself (nobody is locked out for good) and a success clears the count', async () => {
  const u = await s.register('patient');
  for (let i = 0; i < 3; i++) await login(u.username, 'nope-nope');
  assert.equal((await login(u.username, 'secret123')).status, 429);
  await new Promise((r) => setTimeout(r, 2700));
  assert.equal((await login(u.username, 'secret123')).status, 200);
  // two more mistakes after a success do not trip the limit
  await login(u.username, 'bad-bad-1');
  await login(u.username, 'bad-bad-2');
  assert.equal((await login(u.username, 'secret123')).status, 200);
});

test('unknown usernames are counted too, so the limiter does not reveal which accounts exist', async () => {
  for (let i = 0; i < 3; i++) assert.equal((await login('no-such-user-xyz', 'whatever')).status, 401);
  assert.equal((await login('no-such-user-xyz', 'whatever')).status, 429);
});

test('wrong current passwords on change-password count toward the same limit', async () => {
  const u = await s.register('changer');
  for (let i = 0; i < 3; i++) {
    assert.equal((await s.call('POST', '/auth/change-password', { current_password: 'bad-bad-bad', new_password: 'new-password-1' }, u.token)).status, 400);
  }
  assert.equal((await s.call('POST', '/auth/change-password', { current_password: 'secret123', new_password: 'new-password-1' }, u.token)).status, 429);
});
