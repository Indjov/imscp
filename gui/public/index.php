<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2015 by i-MSCP Team <team@i-mscp.net>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

require '../application.php';

\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onLoginScriptStart);

/** @var \Zend\Http\PhpEnvironment\Request $request */
$request = \iMSCP\Core\Application::getInstance()->getRequest();

if (($action = $request->getPost('action'))) {
    init_login(\iMSCP\Core\Application::getInstance()->getEventManager());

    /** @var \iMSCP\Core\Authentication\Authentication $authentication */
    $authentication = \iMSCP\Core\Application::getInstance()->getServiceManager()->get('Authentication');

    switch ($action) {
        case 'logout':
            if ($authentication->hasIdentity()) {
                $adminName = $authentication->getIdentity()->admin_name;
                $authentication->unsetIdentity();
                set_page_message(tr('You have been successfully logged out.'), 'success');
                write_log(sprintf("%s logged out", decode_idna($adminName)), E_USER_NOTICE);
            }
            break;
        case 'login':
            $authResult = $authentication->authenticate();

            if ($authResult->isValid()) {
                write_log(sprintf("%s logged in", $authResult->getIdentity()->admin_name), E_USER_NOTICE);
            } elseif (($messages = $authResult->getMessages())) {
                $messages = format_message($messages);
                set_page_message($messages, 'error');
                write_log(sprintf("Authentication failed. Reason: %s", $messages), E_USER_NOTICE);
            }
    }
}

redirectToUiLevel();

$tpl = new \iMSCP\Core\Template\TemplateEngine();
$tpl->defineDynamic([
    'layout' => 'shared/layouts/simple.tpl',
    'page_message' => 'layout',
    'lostpwd_button' => 'page'
]);

$tpl->assign([
    'productLongName' => tr('internet Multi Server Control Panel'),
    'productLink' => 'http://www.i-mscp.net',
    'productCopyright' => tr('© 2010-2015 i-MSCP Team<br/>All Rights Reserved')
]);

$cfg = \iMSCP\Core\Application::getInstance()->getConfig();

if ($cfg['MAINTENANCEMODE'] && !$request->getQuery('admin')) {
    $tpl->defineDynamic('page', 'message.tpl');
    $tpl->assign([
        'TR_PAGE_TITLE' => tr('i-MSCP - Multi Server Control Panel / Maintenance'),
        'HEADER_BLOCK' => '',
        'BOX_MESSAGE_TITLE' => tr('System under maintenance'),
        'BOX_MESSAGE' => (isset($cfg['MAINTENANCEMODE_MESSAGE']))
            ? preg_replace('/\s\s+/', '', nl2br(tohtml($cfg['MAINTENANCEMODE_MESSAGE'])))
            : tr("We are sorry, but the system is currently under maintenance.\nPlease try again later."),
        'TR_BACK' => tr('Administrator login'),
        'BACK_BUTTON_DESTINATION' => '/index.php?admin=1'
    ]);
} else {
    $tpl->defineDynamic([
        'page' => 'index.tpl',
        'lost_password_support' => 'page',
        'ssl_support' => 'page'
    ]);
    $tpl->assign([
        'TR_PAGE_TITLE' => tr('i-MSCP - Multi Server Control Panel / Login'),
        'TR_LOGIN' => tr('Login'),
        'TR_USERNAME' => tr('Username'),
        'UNAME' => tohtml($request->getPost('uname', ''), 'htmlAttr'),
        'TR_PASSWORD' => tr('Password')
    ]);

    if (
        isset($cfg['PANEL_SSL_ENABLED']) && $cfg['PANEL_SSL_ENABLED'] == 'yes' &&
        $cfg['BASE_SERVER_VHOST_PREFIX'] != 'https://'
    ) {
        $isSecure = isSecureRequest() ? true : false;
        $uri = [
            ($isSecure) ? 'http://' : 'https://',
            $request->getServer('SERVER_NAME'),
            ($isSecure)
                ? (($cfg['BASE_SERVER_VHOST_HTTP_PORT'] == 80) ? '' : ':' . $cfg['BASE_SERVER_VHOST_HTTP_PORT'])
                : (($cfg['BASE_SERVER_VHOST_HTTPS_PORT'] == 443) ? '' : ':' . $cfg['BASE_SERVER_VHOST_HTTPS_PORT'])
        ];
        $tpl->assign([
            'SSL_LINK' => tohtml(implode('', $uri), 'htmlAttr'),
            'SSL_IMAGE_CLASS' => ($isSecure) ? 'i_unlock' : 'i_lock',
            'TR_SSL' => ($isSecure) ? tr('Normal connection') : tr('Secure connection'),
            'TR_SSL_DESCRIPTION' => ($isSecure)
                ? tohtml(tr('Use normal connection (No SSL)'), 'htmlAttr')
                : tohtml(tr('Use secure connection (SSL)'), 'htmlAttr')
        ]);
    } else {
        $tpl->assign('SSL_SUPPORT', '');
    }

    if ($cfg['LOSTPASSWORD']) {
        $tpl->assign('TR_LOSTPW', tr('Lost password'));
    } else {
        $tpl->assign('LOST_PASSWORD_SUPPORT', '');
    }
}

generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
\iMSCP\Core\Application::getInstance()->getEventManager()->trigger(\iMSCP\Core\Events::onLoginScriptEnd, null, [
    'templateEngine' => $tpl
]);
$tpl->prnt();

