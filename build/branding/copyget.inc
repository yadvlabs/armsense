<?php
/*
 * copyget.inc
 *
 * part of armsense (https://github.com/yadvlabs/armsense)
 * Copyright (c) 2026 yadv labs and the armsense contributors
 *
 * Derived from pfSense software
 * Copyright (c) 2004-2013 BSD Perimeter
 * Copyright (c) 2013-2016 Electric Sheep Fencing
 * Copyright (c) 2014-2026 Rubicon Communications, LLC (Netgate)
 * All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * The upstream version of this file downloads an updated copyright notice
 * from the vendor's server on every dashboard load.  armsense ships its
 * notice in copynotice.inc and never contacts a remote server for it; the
 * functions below are kept so callers keep working.
 */

function updatecopyright() {
	return;
}

function compare_copytext($new, $old) {
	return ($new === $old);
}
