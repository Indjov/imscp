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
 * Generates support questions notice for administrator
 *
 * Notice administrator about any new support questions and answers.
 *
 * @return void
 */
function admin_generateSupportQuestionsMessage()
{
    $query = "
        SELECT
            COUNT(ticket_id) AS nbQuestions
        FROM
            tickets
        WHERE
            ticket_to = ?
        AND
            ticket_status IN (1, 2)
        AND
            ticket_reply = 0
    ";
    $stmt = exec_query($query, $_SESSION['user_id']);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    $nbQuestions = $row['nbQuestions'];

    if ($nbQuestions) {
        set_page_message(tr('You have received %s new support ticket(s).', '<strong>' . $nbQuestions . '</strong>'), 'static_info');
    }
}

/**
 * Generates update messages
 *
 * Generates update messages for both database updates and i-MSCP updates.
 *
 * @return void
 */
function admin_generateUpdateMessages()
{
    $cfg = \iMSCP\Core\Application::getInstance()->getConfig();

    if (\iMSCP\Core\Updater\DatabaseUpdater::getInstance()->isAvailableUpdate()) {
        set_page_message('<a href="database_update.php" class="link">' . tr('A database update is available') . '</a>', 'static_info');
    }

    if (isset($cfg['CHECK_FOR_UPDATES']) && $cfg['CHECK_FOR_UPDATES']) {
        $updateVersion = \iMSCP\Core\Updater\VersionUpdater::getInstance();

        if ($updateVersion->isAvailableUpdate()) {
            set_page_message('<a href="imscp_updates.php" class="link">' . tr('A new i-MSCP version is available') . '</a>', 'static_info');
        } elseif (($error = $updateVersion->getError())) {
            set_page_message($error, 'error');
        }
    }
}

/**
 * Generates admin general informations
 *
 * @param  \iMSCP\Core\Template\TemplateEngine $tpl TemplateEngine instance
 * @return void
 */
function admin_getAdminGeneralInfo($tpl)
{
    $cfg = \iMSCP\Core\Application::getInstance()->getConfig();

    // If COUNT_DEFAULT_EMAIL_ADDRESSES == false, admin total emails show [total - default_emails]/[total_emails]
    $totalMails = records_count('mail_users', 'mail_type NOT RLIKE \'_catchall\'', '');

    if ($cfg['COUNT_DEFAULT_EMAIL_ADDRESSES']) {
        $showTotalMails = $totalMails;
    } else {
        $totalDefaultMails = records_count('mail_users', 'mail_acc', 'abuse');
        $totalDefaultMails += records_count('mail_users', 'mail_acc', 'webmaster');
        $totalDefaultMails += records_count('mail_users', 'mail_acc', 'postmaster');
        $showTotalMails = ($totalMails - $totalDefaultMails) . '/' . $totalMails;
    }

    $tpl->assign([
        'ACCOUNT_NAME' => tohtml($_SESSION['user_logged']),
        'ADMIN_USERS' => records_count('admin', 'admin_type', 'admin'),
        'RESELLER_USERS' => records_count('admin', 'admin_type', 'reseller'),
        'NORMAL_USERS' => records_count('admin', 'admin_type', 'user'),
        'DOMAINS' => records_count('domain', '', ''),
        'SUBDOMAINS' => records_count('subdomain', '', '') + records_count('subdomain_alias', 'subdomain_alias_id', ''),
        'DOMAINS_ALIASES' => records_count('domain_aliasses', '', ''),
        'MAIL_ACCOUNTS' => $showTotalMails,
        'FTP_ACCOUNTS' => records_count('ftp_users', '', ''),
        'SQL_DATABASES' => records_count('sql_database', '', ''),
        'SQL_USERS' => get_sql_user_count()
    ]);
}

/**
 * Generates server traffic bar
 *
 * @param  \iMSCP\Core\Template\TemplateEngine $tpl TemplateEngine instance
 * @return void
 */
function admin_generateServerTrafficInfo($tpl)
{
    $cfg = \iMSCP\Core\Application::getInstance()->getConfig();
    $trafficLimitBytes = ($cfg['SERVER_TRAFFIC_LIMIT']) ? $cfg['SERVER_TRAFFIC_LIMIT'] * 1048576 : 0;
    $trafficWarningBytes = ($cfg['SERVER_TRAFFIC_WARN']) ? $cfg['SERVER_TRAFFIC_WARN'] * 1048576 : 0;

    if (!$trafficWarningBytes) {
        $trafficWarningBytes = $trafficLimitBytes;
    }

    // Getting server traffic usage value in bytes for the current month
    $query = "
		SELECT
			IFNULL((SUM(bytes_in) + SUM(bytes_out)), 0) AS serverTrafficUsage
		FROM
			server_traffic
		WHERE
			traff_time BETWEEN ? AND ?
    ";
    $stmt = exec_query($query, [getFirstDayOfMonth(), getLastDayOfMonth()]);

    if ($stmt->rowCount()) {
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $trafficUsageBytes = $row['serverTrafficUsage'];
    } else {
        $trafficUsageBytes = 0;
    }

    // Get traffic usage in percent
    $trafficUsagePercent = make_usage_vals($trafficUsageBytes, $trafficLimitBytes);

    if ($trafficLimitBytes) {
        $trafficMessage = tr(
            '%1$s%% [%2$s of %3$s]', $trafficUsagePercent, bytesHuman($trafficUsageBytes), bytesHuman($trafficLimitBytes)
        );
    } else {
        $trafficMessage = tr('%1$s%% [%2$s of unlimited]', $trafficUsagePercent, bytesHuman($trafficUsageBytes));
    }

    // Warning message about traffic
    if ($trafficUsageBytes) {
        if (($trafficWarningBytes && $trafficUsageBytes > $trafficWarningBytes) ||
            // In any case, display a warning if traffic limit is reached
            ($trafficLimitBytes && $trafficUsageBytes > $trafficLimitBytes)
        ) {
            set_page_message(tr('You are exceeding the monthly server traffic limit.'), 'static_warning');
        }
    }

    $tpl->assign([
        'TRAFFIC_WARNING' => $trafficMessage,
        'TRAFFIC_PERCENT' => $trafficUsagePercent
    ]);
}

/***********************************************************************************************************************
 * Main
 */

require '../../application.php';

\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onAdminScriptStart);

check_login('admin', $cfg['PREVENT_EXTERNAL_LOGIN_ADMIN']);

$tpl = new \iMSCP\Core\Template\TemplateEngine();
$tpl->defineDynamic([
    'layout' => 'shared/layouts/ui.tpl',
    'page' => 'admin/index.tpl',
    'page_message' => 'layout',
    'traffic_warning_message' => 'page'
]);
$tpl->assign([
    'TR_PAGE_TITLE' => tr('Admin / General / Overview'),
    'TR_PROPERTIES' => tr('Properties'),
    'TR_VALUES' => tr('Values'),
    'TR_ACCOUNT_NAME' => tr('Account name'),
    'TR_ADMIN_USERS' => tr('Admin users'),
    'TR_RESELLER_USERS' => tr('Reseller users'),
    'TR_NORMAL_USERS' => tr('Normal users'),
    'TR_DOMAINS' => tr('Domains'),
    'TR_SUBDOMAINS' => tr('Subdomains'),
    'TR_DOMAINS_ALIASES' => tr('Domain aliases'),
    'TR_MAIL_ACCOUNTS' => tr('Email accounts'),
    'TR_FTP_ACCOUNTS' => tr('FTP accounts'),
    'TR_SQL_DATABASES' => tr('SQL databases'),
    'TR_SQL_USERS' => tr('SQL users'),
    'TR_SERVER_TRAFFIC' => tr('Server traffic')
]);

generateNavigation($tpl);
admin_generateSupportQuestionsMessage();
admin_generateUpdateMessages();
admin_getAdminGeneralInfo($tpl);
admin_generateServerTrafficInfo($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onAdminScriptEnd, null, [
    'templateEngine' => $tpl
]);
$tpl->prnt();

unsetMessages();
