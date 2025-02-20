%基于 online adaptive optimization 的轨迹估计函数
%使用加速度模型
function [As_up,Qs_up,Rzs_up,cut_t,Xs_up,dX_up,preX]=OAOestimationAcc(As,Qs,Rzs_ob,Rzs,H,cut_t,Xs,dX,Zs,sitar,time)
%@As 状态转移矩阵
%@Qs 观测协方差
%@Rzs_ob 观测方差的初始值
%@Rzs 修正后的观测方差
%@H 观测矩阵
%@cut_t 截断时刻
%@Xs 轨迹状态
%@dX 转移误差
%@Zs 观测
%@sitar 参数
%@time 时间

% 参数准备
palpha=sitar.alpha;
pbeta=sitar.beta;
Da=sitar.Da;

[~,nx]=size(Xs);
[~,nz]=size(Zs);

if(nz<=nx)
    preX=-1;    %观测信息不足以滤波，报错误
    disp('error:观测信息不足，无法完成滤波，请检查观测信息');
    return;
end

% 1.更新状态转移矩阵
As_up=[As(1:nx);cell(1)];
Qs_up=[Qs(1:nx);cell(1)];
for i=cut_t+1:nx-1
    dt=time(i+1)-time(i);
    As_up{i}=AccModel(Xs(:,i),dt,palpha,pbeta);
end

% 2.更新最后一个协方差
if(nx>0)
    dt=time(nx+1)-time(nx);
    [As_up{nx},Qs_up{nx}]=transModel(Xs(:,nx),dt,palpha,pbeta,Da);
end

% 3.轨迹预测
if(nx==0)
    preX=zeros(9,1);
    preX(1:3,1)=Zs(1:3,1);
    preX(4:6,1)=(rand(3,1)-0.5);
else
    preX=As_up{nx}*Xs(:,nx);
end

% 4.更新观测方差
Rzs_up=observCovUpdate(Rzs_ob,Rzs,H,cut_t,[Xs,preX],Zs);

% 5.计算新的轨迹
Xs_up=MAPestimation(As_up,Qs_up,Rzs_up,H,cut_t,Xs,Zs,time);

% 6.更新状态转移方差
dX_up=stransError(As_up,Xs_up,dX,cut_t);  %更新转移误差
% Qs_up=transCovUpdate(Qs_up,dX_up,time,cut_t);

% 7.截断时刻更新
Fiy=diag([1,1,1,1/4,1/4,1/4,1/9,1/9,1/9]);
cut_t=cutTimeUpdate([Xs,preX],Xs_up,Fiy,cut_t);

end

function A=AccModel(x,dt,palpha,pbeta)
%  计算状态转移矩阵A
%  输入： 上一时刻状态向量x 时间间隔dt 阻尼因子 palpha,pbeta
%  输出：状态转移矩阵A

%数据准备
n=length(x);
A=eye(n,n);

%基本参数
v=x(4:6);   %速度分量
v2=v'*v;
if(v2<0.0001)
    v2=0.0001;
end
va=sqrt(v2);

exp_at=exp(-palpha*dt);
exp_at1=(1-exp_at)/palpha;
exp_at2=(dt-exp_at1)/palpha;

A(1:3,4:6)=eye(3)*(exp_at1-exp_at2*pbeta/va);
A(1:3,7:9)=eye(3)*exp_at2/va;
A(4:6,4:6)=eye(3)*(exp_at-exp_at1*pbeta/va);
A(4:6,7:9)=eye(3)*exp_at1/va;

end

function [A,Q]=transModel(x,dt,palpha,pbeta,Da)
%数据准备
n=length(x);
A=eye(n,n);

%基本参数
v=x(4:6);   %速度分量
v2=v'*v;
if(v2<0.0001)
    v2=0.0001;
end
va=sqrt(v2);

exp_at=exp(-palpha*dt);
exp_at1=(1-exp_at)/palpha;
exp_at2=(dt-exp_at1)/palpha;

A(1:3,4:6)=eye(3)*(exp_at1-exp_at2*pbeta/va);
A(1:3,7:9)=eye(3)*exp_at2/va;
A(4:6,4:6)=eye(3)*(exp_at-exp_at1*pbeta/va);
A(4:6,7:9)=eye(3)*exp_at1/va;

% 方差
Q=zeros(n,n);
Q(1:3,1:3)=Da*dt*exp_at2^2/5;
Q(1:3,4:6)=Da*dt*exp_at2*exp_at1/4;
Q(1:3,7:9)=Da*dt*exp_at2/5;

Q(4:6,4:6)=Da*dt*exp_at1^2/3;
Q(4:6,7:9)=Da*dt*exp_at1/2;
Q(7:9,7:9)=Da*dt;

%对称化
for i=1:n
    for j=i+1:n
        Q(j,i)=Q(i,j);
    end
end

for i=1:n
    Q(i,i)=Q(i,i)*n/2;
end

end

% 4.更新观测方差
function Rzs=observCovUpdate(Rzs_ob,Rzs,H,cut_t,Xs,Zs)
[nr,lz]=size(Rzs);
mz=size(Zs,1);

if(nr<1)
    return;
end

% 计算观测误差
dz=zeros(mz,nr-cut_t,lz);
rz=zeros(nr-cut_t,lz);
for i=cut_t+1:nr
    id=i-cut_t;
    for j=1:lz
        cur_dz=H*Xs(:,i)-Zs(:,i,j);
        dz(:,id,j)=cur_dz;
        rz(id,j)=cur_dz'/Rzs_ob{i,j}*cur_dz;
    end
end

h_rz=min([3*sqrt(mean(mean(rz.^2))),16]);

for i=cut_t+1:nr
    id=i-cut_t;
    for j=1:lz
        if(rz(id,j)>h_rz)
            Rzs{i,j}=Rzs_ob{i,j}/2+dz(:,id,j)*dz(:,id,j)';
        else
            Rzs{i,j}=Rzs_ob{i,j};
        end
    end
end

end

% 5.计算新的轨迹
function Xs_up=MAPestimation(As,Qs,Rzs,H,cut_t,Xs,Zs,time)
%  trajectory MAP from observations
%  输入：离散状态转移矩阵集合As,状态转移协方差矩阵集合Qs,
%       观测协方差矩阵Rzs,观测矩阵H,截断时刻cut_t,上一时刻轨迹估计Xs,观测Zs
%  输出：状态轨迹X_re

n=length(As);  %状态时刻数
[nz,lz]=size(Rzs);%观测时刻数及同一时刻观测个数
if(nz<n)
    disp('error->in maxLikelihoodFilter 观测个数过少，无法求解');
    return;
end
if(n==0)
    disp('error->in maxLikelihoodFilter 状态转移矩阵数目小于1 无法求解');
    return;
end

%只有少许状态，直接计算初始值
if n<=6
    Xs_up=0.1*(rand(9,n)-0.5);
    for i=1:n
        Xs_up(1:3,i)=positionFromObserv(Zs(:,i,:),Rzs(i,:));
        
        if i>=2
            Xs_up(4:6,i-1)=Xs_up(4:6,i-1)+(Xs_up(1:3,i)-Xs_up(1:3,i-1))/(time(i)-time(i-1));%速度
        end
    end
    
    if n>=2
        Xs_up(4:6,i)=Xs_up(4:6,i)+Xs_up(4:6,i-1);
    end
    
    return;
end

if n>80
    cut_t=max(cut_t,2);
end

%1.包含多个状态的迭代求解
%(1)计算方差的逆
n_use=n-cut_t;

Qs_inv=cell(n_use,1);
Rs_inv=cell(n_use,lz);

for i=1:n_use
    t=cut_t+i;  %时间戳
    
    Q=Qs{t};    %状态转移协方差
    Qs_inv{i}=inv(Q);   %逆矩阵
    
    for j=1:lz
        Rs_inv{i,j}=inv(Rzs{t,j});  %观测协方差逆
    end
end

if(cut_t>0) %前一个协方差阵求逆
    Qp_inv=inv(Qs{cut_t});
end

% (2)系数矩阵与向量的各个分量
m=size(Xs,1);

Mc=cell(n_use,1);   %M的对角元
Ms=cell(n_use,1);   %M的非对角元
b=zeros(m,n_use);   %每列同一个时刻，行方向为时间轴

% 第一个时刻
t=cut_t+1;
xm_Mat=As{t}'*Qs_inv{1};
Ms{1}=xm_Mat;
b_cr=Rs_inv{1,1}*Zs(:,1,1);
sum_Rs=Rs_inv{1,1};
t=cut_t+1;
for j=2:lz
    sum_Rs=sum_Rs+Rs_inv{1,j};
    b_cr=b_cr+Rs_inv{1,j}*Zs(:,t,j);
end
Mc{1}=H'*sum_Rs*H+xm_Mat*As{t};
b(:,1)=H'*b_cr;

if(cut_t>0)    %截断时刻生效
    Mc{1}=Mc{1}+Qp_inv; %t==cut_t
    b(:,1)=b(:,1)+Qp_inv*As{cut_t}*Xs(:,cut_t);
end

% 后续时刻
for i=2:n_use-1
    t=cut_t+i;  %时间戳
    xm_Mat=As{t}'*Qs_inv{i};
    Ms{i}=xm_Mat;
    sum_Rs=Rs_inv{i,1};
    b_cr=Rs_inv{i,1}*Zs(:,t,1);
    
    for j=2:lz
        sum_Rs=sum_Rs+Rs_inv{i,j};
        b_cr=b_cr+Rs_inv{i,j}*Zs(:,t,j);
    end
    
    Mc{i}=H'*sum_Rs*H+xm_Mat*As{t}+Qs_inv{i-1}; %n_use<t<k
    b(:,i)=H'*b_cr;
end

%t==k
t=cut_t+n_use;
sum_Rs=Rs_inv{n_use,1};
b_cr=Rs_inv{n_use,1}*Zs(:,t,1);

for j=2:lz
    sum_Rs=sum_Rs+Rs_inv{n_use,j};
    b_cr=b_cr+Rs_inv{n_use,j}*Zs(:,t,j);
end
Mc{n_use}=H'*sum_Rs*H+Qs_inv{n_use-1};
b(:,n_use)=H'*b_cr;

%2.根据观测值校正轨迹
% (1)正序消元
for i=1:n_use-1
    cg=Ms{i}'/Mc{i};
    Mc{i+1}=Mc{i+1}-cg*Ms{i};
    b(:,i+1)=b(:,i+1)+cg*b(:,i);
end

% (3)逆序推算
X_up=zeros(m,n_use);	%X更新部分
X_up(:,n_use)=Mc{n_use}\b(:,n_use);

if isnan(X_up(1,n_use))
    t=cut_t+n_use;
    X_up(:,n_use)=Xs(:,t-1);
    X_up(1:3,n_use)=positionFromObserv(Zs(:,t,:),Rzs(t,:));
    X_up(4:6,n_use)=(X_up(1:3,n_use)-X_up(1:3,n_use-1))/(time(t)-time(t-1));
end

for i=n_use-1:-1:1
    X_up(:,i)=Mc{i}\(b(:,i)+Ms{i}*X_up(:,i+1));
    if isnan(X_up(1,i))
        X_up(:,1:i)=Xs(:,cut_t+1:cut_t+i)+0.04*(rand(9,i)-0.5);
        break;
    end
end

% 输出更新
Xs_up=[Xs(:,1:cut_t),X_up];
end

% 计算状态转移误差
function dX_re=stransError(As,Xs,dX,cut_t)
n=length(As);
% 状态转移误差
dX_re=[dX,zeros(9,1)];
for i=cut_t+1:n-1
    dX_re(:,i)=As{i}*Xs(:,i)-Xs(:,i+1);
end
end

% 状态转移方差更新函数
function Qs=transCovUpdate(Qs,delta_x,time,cut_t)
% 输入：状态转移矩阵Qs 当前轨迹状态转移误差delta_x 采样时刻time 
%       截断时刻cut_t 当前机动tm

nt=length(Qs);
if(nt<2)
    return;
end

time_use=time(nt)-time(cut_t+1);
dt=time(nt)-time(nt-1);

for i=cut_t+1:nt-1
    dd=delta_x(:,i);%-delta_pr(:,i);
    Qs{i}=(time_use*Qs{i}+(dt*dd)*dd')/(time_use+dt);
end

end

% 截断时刻更新
function cut_t=cutTimeUpdate(Xs_pre,Xs_ev,Fiy,cut_tp)
%  输入：状态轨迹预测Xs_pre 状态轨迹估计Xs_ev 权重矩阵Fiy 前一个截断时刻cut_tp
%  输出：截断时刻cut_t

[~,n]=size(Xs_pre);
ang=0.0001;        %误差限

sum_eer=0;

for i=cut_tp+1:2:n-40   %隔两个时刻一次采样
    error=Xs_pre(:,i)-Xs_ev(:,i);
    if sum_eer==0
        sum_eer=error'*Fiy*error;
    else
        sum_eer=0.95*sum_eer+0.05*error'*Fiy*error;
    end
    if(sum_eer>ang)    %平均误差大于阈值
        cut_t=max(i-20,0);
        return;
    end
end
cut_t=max(n-50,0);
end

function p=positionFromObserv(zs,Rz)
lz=length(Rz);%观测时刻数及同一时刻观测个数

p=zeros(3,1);
sum_w=zeros(3,3);

for j=1:lz
    iv_Rz=inv(Rz{j});
    p=p+iv_Rz*zs(:,j);
    sum_w=sum_w+iv_Rz;
end

p=sum_w\p;
end
