<?php
/*
 * copynotice.inc
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

##|+PRIV
##|*IDENT=page-system-copyright
##|*NAME=System: Copyright notice
##|*DESCR=Copyright and usage notice.
##|*MATCH=copynotice.inc*
##|-PRIV

/*
 * This file displays the license and attribution modal when required
 * (new version installed or completion of the setup wizard).
 */
?>
<div id="usage" class="modal fade" role="dialog">
	<div class="modal-dialog modal-lg">
		<div class="modal-content">
			<div id="main1" class="modal-body modal-lg modal-dialog-scrollable" style="background-color:#1b1b1b; color:white;">
				<p style="font-size:16px">
					<b><?=g_get('product_label')?></b>
				</p>
				<p>
					<?=g_get('product_label')?> is free and open source software, distributed under the
					<a target="_blank" href="http://www.apache.org/licenses/LICENSE-2.0" style="color:#9fc5ff">Apache License, Version 2.0</a>.
					Copyright<sup>&copy;</sup> 2026 yadv labs and the <?=g_get('product_label')?> contributors.
				</p>
				<p style="font-size:16px">
					<b>Attribution.</b>
				</p>
				<p>
					<?=g_get('product_label')?> is derived from the pfSense<sup>&reg;</sup> Community Edition source code,
					Copyright<sup>&copy;</sup> 2004-2016 Electric Sheep Fencing, LLC and
					Copyright<sup>&copy;</sup> 2014-2026 Rubicon Communications, LLC (Netgate), used under the Apache License, Version 2.0.
					"pfSense" is a registered trademark of Electric Sheep Fencing, LLC.
					<?=g_get('product_label')?> is an independent project and is not affiliated with, sponsored by, or endorsed by Netgate or Electric Sheep Fencing.
					It also includes FreeBSD and many other open source components; their licenses are listed in /usr/local/share/licenses on this system.
				</p>
				<p style="font-size:16px">
					<b>No warranty.</b>
				</p>
				<p>
					Unless required by applicable law or agreed to in writing, this software is distributed on an "AS IS" BASIS,
					WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific
					language governing permissions and limitations under the License.
				</p>
				<p>
					Project home: <a target="_blank" href="https://labs.yadv.in/" style="color:#9fc5ff">https://labs.yadv.in/</a><br />
					Source code: <a target="_blank" href="https://github.com/yadvlabs/armsense" style="color:#9fc5ff">https://github.com/yadvlabs/armsense</a>
				</p>
			</div>

			<div id="f1" class="modal-footer modal-lg" style="background-color:#1b1b1b; color:white;">
				<button type="button" class="btn btn-xs btn-success" aria-label="Close" onClick="$('.modal').modal('hide');">
					<span aria-hidden="true">
						Accept
					</span>
				</button>
			</div>

		</div>
	</div>
</div>

<script type="text/javascript">
//<![CDATA[
events.push(function() {
	$('#usage').modal({backdrop: 'static', keyboard: false});
	$('#usage').modal('show');
});
//]]>
</script>
