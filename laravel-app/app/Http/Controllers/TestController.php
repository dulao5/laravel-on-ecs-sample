<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\TestModel;

class TestController extends Controller
{
    public function testDatabaseConnection(Request $request)
    {
        $dbtype = $request->query('dbtype', 'aurora');

        if (!in_array($dbtype, ['aurora', 'tidb'])) {
            return response()->json(['error' => 'Invalid dbtype'], 400);
        }

        config(['database.default' => $dbtype]);

        $randomId = rand(1, 1000);
        $randomUserId = rand(1, 1000);

        // 使用 find 方法查询数据
        $result1 = TestModel::find($randomId);
        $results = TestModel::where('user_id', $randomUserId)->get();

        // 返回查询结果
        return response()->json([$result1, $results]);
    }
}
