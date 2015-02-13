# rej.pl

## 概要

    rej.pl -k <key> -c <command>                : 多重起動防止で command 実行
    
    rej.pl -i                                   : 一覧表示
    
    rej.pl -k <key>                             : 履歴表示
    
    rej.pl --clear (aben|lock|hist) [-k <key>]  : システムファイル削除

多重起動防止。rej.pl 経由でコマンドを実行（実行形式である必要がある）。
別のコマンドであろうが、rej.pl は key に対して１つしか起動できない。

コマンドの実行履歴を確認することが出来る。

config に設定すれば、AbEnd（abnormal end）時にメールを送信することが出来る。
連続して AbEnd した場合、メール送信するのは初回のみ。

## インストール方法

### 1. rej.conf の内容を適宜変更

$conf->{log}{dir} にログなどを憶ディレクトリを指定する。必須。

AbEnd（異常終了）時にメールを送りたい場合は、$conf->{mail}{send} に 1 を指定。送りたくない場合は 0 を指定。

$conf->{mail}{to}, $conf->{mail}{from} にメールアドレスを指定。カンマ区切りで複数指定可能。

$conf->{mail}{subject} にはメールのタイトルを指定。空文字でもOK。

$conf->{mail}{hist_log_size} にはメール本文に書かれるログのサイズを指定。

    {
        # ログなどを置くディレクトリを指定する。必須。
        log     => +{
            dir             => '/your/log/dir/rej',
        },
        # AbEnd 時に送るメールについての設定。
        mail    => +{
            send            => 1,
            to              => 'to@email.address',
            from            => 'from@email.address',
            subject         => '',
            hist_log_size   => 100,
        },
    }

### 2. rej.conf を適宜配置

    mv rej.conf /your/conf/dir

### 3. rej.pl の 13 行目あたりを変更し、rej.conf のフルパスを指定する。

    my $path_conf   = '/your/conf/dir/rej.conf';

### 4. rej.pl を適宜配置

    mv rej.pl /your/util/dir
