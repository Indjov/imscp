<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 *
 * The contents of this file are subject to the Mozilla Public License
 * Version 1.1 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * The Original Code is "VHCS - Virtual Hosting Control System".
 *
 * The Initial Developer of the Original Code is moleSoftware GmbH.
 * Portions created by Initial Developer are Copyright (C) 2001-2006
 * by moleSoftware GmbH. All Rights Reserved.
 *
 * Portions created by the ispCP Team are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 *
 * Portions created by the i-MSCP Team are Copyright (C) 2010-2015 by
 * i-MSCP - internet Multi Server Control Panel. All Rights Reserved.
 */

/***********************************************************************************************************************
 * Functions
 */

/**
 * Generate reseller table
 *
 * @param \iMSCP\Core\Template\TemplateEngine $tpl
 */
function gen_reseller_table($tpl)
{
    $cfg = \iMSCP\Core\Application::getInstance()->getConfig();
    $query = "
        SELECT
            t1.`admin_id`, t1.`admin_name`, t2.`admin_name` AS created_by
        FROM
            `admin` AS t1, `admin` AS t2
        WHERE
            t1.`admin_type` = 'reseller'
        AND
            t1.`created_by` = t2.`admin_id`
        ORDER BY
            `created_by`, `admin_id`
    ";
    $rs = execute_query($query);
    $i = 0;

    if (!$rs->rowCount()) {
        $tpl->assign([
            'MESSAGE' => tr('Reseller list is empty.'),
            'RESELLER_LIST' => '',
        ]);

        $tpl->parse('PAGE_MESSAGE', 'page_message');
    } else {
        while ($row = $rs->fetch(PDO::FETCH_ASSOC)) {
            $admin_id = $row['admin_id'];
            $admin_id_var_name = "admin_id_" . $admin_id;
            $tpl->assign([
                'NUMBER' => $i + 1,
                'RESELLER_NAME' => tohtml($row['admin_name']),
                'OWNER' => tohtml($row['created_by']),
                'CKB_NAME' => $admin_id_var_name,
            ]);
            $tpl->parse('RESELLER_ITEM', '.reseller_item');
            $i++;
        }

        $tpl->parse('RESELLER_LIST', 'reseller_list');
        $tpl->assign('PAGE_MESSAGE', '');
    }

    $query = "
        SELECT
            `admin_id`, `admin_name`
        FROM
            `admin`
        WHERE
            `admin_type` = 'admin'
        ORDER BY
            `admin_name`
    ";
    $rs = execute_query($query);

    while ($row = $rs->fetch(PDO::FETCH_ASSOC)) {
        if ((isset($_POST['uaction']) && $_POST['uaction'] === 'reseller_owner') && (isset($_POST['dest_admin']) &&
                $_POST['dest_admin'] == $row['admin_id'])
        ) {
            $selected = $cfg['HTML_SELECTED'];
        } else {
            $selected = '';
        }

        $tpl->assign([
            'OPTION' => tohtml($row['admin_name']),
            'VALUE' => $row['admin_id'],
            'SELECTED' => $selected
        ]);
        $tpl->parse('SELECT_ADMIN_OPTION', '.select_admin_option');
        $i++;
    }

    $tpl->parse('SELECT_ADMIN', 'select_admin');
    $tpl->assign('PAGE_MESSAGE', '');
}

/**
 * Update reseller owner
 *
 * @return void
 */
function update_reseller_owner()
{
    if (isset($_POST['uaction']) && $_POST['uaction'] === 'reseller_owner') {
        $query = "
            SELECT
                `admin_id`
            FROM
                `admin`
            WHERE
                `admin_type` = 'reseller'
            ORDER BY
                `admin_name`
        ";
        $rs = execute_query($query);

        while ($row = $rs->fetch(PDO::FETCH_ASSOC)) {
            $admin_id = $row['admin_id'];
            $admin_id_var_name = "admin_id_$admin_id";

            if (isset($_POST[$admin_id_var_name]) && $_POST[$admin_id_var_name] === 'on') {
                $dest_admin = $_POST['dest_admin'];
                $query = "UPDATE `admin` SET `created_by` = ? WHERE `admin_id` = ?";
                exec_query($query, [$dest_admin, $admin_id]);
            }
        }
    }
}

/***********************************************************************************************************************
 * Main
 */

require '../../application.php';

\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onAdminScriptStart);

check_login('admin');

$tpl = new \iMSCP\Core\Template\TemplateEngine();
$tpl->define_dynamic([
    'layout' => 'shared/layouts/ui.tpl',
    'page' => 'admin/manage_reseller_owners.tpl',
    'page_message' => 'layout',
    'hosting_plans' => 'page',
    'reseller_list' => 'page',
    'reseller_item' => 'reseller_list',
    'select_admin' => 'page',
    'select_admin_option' => 'select_admin'
]);
$tpl->assign([
    'TR_PAGE_TITLE', tr('Admin / Users / Resellers Assignment'),
    'TR_RESELLER_ASSIGNMENT' => tr('Reseller assignment'),
    'TR_RESELLER_USERS' => tr('Reseller users'),
    'TR_NUMBER' => tr('No.'),
    'TR_MARK' => tr('Mark'),
    'TR_RESELLER_NAME' => tr('Reseller name'),
    'TR_OWNER' => tr('Owner'),
    'TR_TO_ADMIN' => tr('To Admin'),
    'TR_MOVE' => tr('Move')
]);

generateNavigation($tpl);
update_reseller_owner();
gen_reseller_table($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onAdminScriptEnd, [
    'templateEngine' => $tpl
]);
$tpl->prnt();

unsetMessages();
