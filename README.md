<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

# Bloc

<details>
<summary>Avoid Emit After Await</summary>

**Lint Name**: `avoid_emit_after_await`

**Description**:  
This lint rule ensures that `emit` calls in a `Bloc` are properly guarded by a check for `isClosed` when they occur after an `await` expression. This prevents potential runtime errors caused by emitting states to a closed `Bloc`.

---

### Problem

When using `emit` in a `Bloc`, if the `Bloc` is closed after an `await` operation, calling `emit` will throw an exception. This lint rule ensures that all `emit` calls after an `await` are wrapped in a guard like `if (!isClosed)`.

---

### Example

#### Bad Code:
```dart
Future<void> someAsyncFunction() async {
  await Future.delayed(Duration(seconds: 1));
  emit(SomeState()); // This can throw if the Bloc is closed
}
```

#### Good Code:
```dart
Future<void> someAsyncFunction() async {
  await Future.delayed(Duration(seconds: 1));
  if (!isClosed) {
    emit(SomeState()); // Safe to emit
  }
}
```

</details>

---


# GetIt

<details>
<summary>Check GetIt Instance Registered</summary>

**Lint Name**: `check_get_it_instance_registered`

**Description**:  
This lint rule ensures that calls to `GetIt.I<T>()` are properly guarded by a check for `isRegistered<T>()` before retrieving the instance. This prevents potential runtime errors caused by attempting to retrieve an unregistered dependency.

---

### Problem

When retrieving instances from GetIt's service locator using `GetIt.I<T>()`, if the type is not registered, it will throw a runtime exception. This lint rule ensures that all retrievals are preceded by a check to ensure the type is registered before accessing it.

---

### Example

#### Bad Code:
```dart
void someFunction() {
  final controller = GetIt.I<Controller>(); // This can throw if Controller is not registered
  controller.doSomething();
}
```

#### Good Code:
```dart
void someFunction() {
  if (GetIt.I.isRegistered<Controller>()) {
    final controller = GetIt.I<Controller>(); // Safe to retrieve
    controller.doSomething();
  }
}
```

#### Alternative Good Code:
```dart
void someFunction() {
  if (!GetIt.I.isRegistered<Controller>()) return;
  
  final controller = GetIt.I<Controller>(); // Safe to retrieve
  controller.doSomething();
}
```

---

### Fix

The lint rule provides an automatic fix that wraps the `GetIt.I<T>()` call in an `if (GetIt.I.isRegistered<T>())` check.

#### Example Fix:
##### Input:
```dart
final controller = GetIt.I<Controller>();
controller.doSomething();
```

##### Output:
```dart
if (GetIt.I.isRegistered<Controller>()) {
  final controller = GetIt.I<Controller>();
  controller.doSomething();
}
```

</details>

---

# Hive

<details>
<summary>Check Hive Box Is Open</summary>

**Lint Name**: `check_hive_box_is_open`

**Description**:  
This lint rule ensures that operations on a Hive box (e.g., `put`, `delete`, `add`) are properly guarded by a check for `isOpen`. This prevents potential runtime errors caused by attempting to modify a closed Hive box.

---

### Problem

When performing operations on a Hive box, if the box is closed, it can throw runtime exceptions. This lint rule ensures that all modifying operations on a Hive box are preceded by a check to ensure the box is open.

---

### Example

#### Bad Code:
```dart
void saveData(Box box) {
  box.put('key', 'value'); // This can throw if the box is closed
}
```

#### Good Code:
```dart
void saveData(Box box) {
  if (box.isOpen) {
    box.put('key', 'value'); // Safe to modify the box
  }
}
```

#### Alternative Good Code:
```dart
void saveData(Box box) {
  if (!box.isOpen) return;
  box.put('key', 'value'); // Safe to modify the box
}
```

---

### Fix

The lint rule provides an automatic fix that wraps the Hive box operation in an `if (box.isOpen)` check.

#### Example Fix:
##### Input:
```dart
box.put('key', 'value');
```

##### Output:
```dart
if (box.isOpen) {
  box.put('key', 'value');
}
```

</details>



<details>
<summary>Avoid Dynamic Hive Box</summary>

**Lint Name**: `avoid_dynamic_hive_box`

**Description**:  
This lint rule ensures that Hive boxes are created with explicit type parameters rather than using implicit dynamic types. This promotes type safety and prevents potential runtime errors caused by storing or retrieving values of unexpected types.

---

### Problem

When creating Hive boxes without specifying type parameters (e.g., `Hive.openBox('myBox')` instead of `Hive.openBox<String>('myBox')`), the box defaults to using `dynamic` types. This can lead to type errors at runtime when accessing data and bypasses Dart's static type checking, making your code less safe and harder to maintain.

---

### Example

#### Bad Code:
```dart
final box = await Hive.openBox('settings');
final lazyBox = await Hive.openLazyBox('contacts');
```
#### Good Code:
```dart
final box = await Hive.openBox<String>('settings');
final lazyBox = await Hive.openLazyBox<Contact>('contacts');
```

</details>

---

# Widget

<details>
<summary>Wrap Text in Row</summary>

**Lint Name**: `wrap_text_in_row`

**Description**:  
This lint rule ensures that `Text` widgets inside a `Row` are wrapped with `Flexible` or `Expanded` to prevent overflow issues. This is particularly important when the `Row` does not have constraints on its width, which can cause the `Text` widget to overflow and result in runtime layout errors.

---

### Problem

When placing a `Text` widget directly inside a `Row`, it can overflow if the text content is too long and the `Row` does not have sufficient constraints. Wrapping the `Text` widget with `Flexible` or `Expanded` ensures that the text is properly constrained and avoids layout issues.

---

### Example

#### Bad Code:
```dart
Row(
  children: [
    Text('This is a very long text that might overflow'),
    Icon(Icons.check),
  ],
);
```

#### Good Code:
```dart
Row(
  children: [
    Flexible(
      child: Text('This is a very long text that might overflow'),
    ),
    Icon(Icons.check),
  ],
);
```

---

### Fix

The lint rule provides an automatic fix that wraps the `Text` widget with a `Flexible` widget.

#### Example Fix:
##### Input:
```dart
Text('This is a very long text that might overflow');
```

##### Output:
```dart
Flexible(
  child: Text('This is a very long text that might overflow'),
);
```

</details>

---



## Enabling the Rules

To enable these lint rules, add them to your `analysis_options.yaml` file:

```yaml
analyzer:
  plugins:
    - custom_lint

custom_lint:
  rules:
    - avoid_emit_after_await
    - check_hive_box_is_open
    - wrap_text_in_row
```