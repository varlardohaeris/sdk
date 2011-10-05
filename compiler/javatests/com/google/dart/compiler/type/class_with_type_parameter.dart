// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

interface A {}

interface B extends A {}

class ClassWithTypeParameter<T extends B> {
  A aField;
  B bField;
  T tField;
}
