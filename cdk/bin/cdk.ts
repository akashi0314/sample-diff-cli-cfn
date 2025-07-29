#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CdkStack } from '../lib/cdk-stack';
import { VpcEc2Stack } from '../lib/vpc-ec2-stack';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

const app = new cdk.App();

// 環境設定
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: 'us-east-1',  // 直接指定
};

// 開発環境
new VpcEc2Stack(app, 'CdkVpcEc2DevStack', {
  env,
  projectTag: 'cdk',
  environmentTag: 'development',
  vpcCidr: '10.0.0.0/16',
  privateSubnetCidr: '10.0.1.0/24',
  availabilityZone: 'us-east-1a',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
  tags: {
    Project: 'cdk',
    Environment: 'development',
    Owner: 'DevTeam'
  }
});

// ステージング環境
new VpcEc2Stack(app, 'CdkVpcEc2StagingStack', {
  env,
  projectTag: 'cdk',
  environmentTag: 'staging',
  vpcCidr: '10.1.0.0/16',
  privateSubnetCidr: '10.1.1.0/24',
  availabilityZone: 'us-east-1b',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
  tags: {
    Project: 'cdk',
    Environment: 'staging',
    Owner: 'DevTeam'
  }
});

// 本番環境（コメントアウト - 慎重にデプロイ）
/*
new VpcEc2Stack(app, 'CdkVpcEc2ProdStack', {
  env,
  projectTag: 'cdk',
  environmentTag: 'production',
  vpcCidr: '10.2.0.0/16',
  privateSubnetCidr: '10.2.1.0/24',
  availabilityZone: 'us-east-1c',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
  tags: {
    Project: 'cdk',
    Environment: 'production',
    Owner: 'DevTeam'
  }
});
*/